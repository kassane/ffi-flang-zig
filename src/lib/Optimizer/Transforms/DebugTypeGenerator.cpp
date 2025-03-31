//===-- DebugTypeGenerator.cpp -- type conversion ---------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Coding style: https://mlir.llvm.org/getting_started/DeveloperGuide/
//
//===----------------------------------------------------------------------===//

#define DEBUG_TYPE "flang-debug-type-generator"

#include "DebugTypeGenerator.h"
#include "flang/Optimizer/CodeGen/DescriptorModel.h"
#include "flang/Optimizer/CodeGen/TypeConverter.h"
#include "flang/Optimizer/Support/DataLayout.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/Support/Debug.h"

namespace fir {

/// Calculate offset of any field in the descriptor.
template <int DescriptorField>
std::uint64_t getComponentOffset(const mlir::DataLayout &dl,
                                 mlir::MLIRContext *context,
                                 mlir::Type llvmFieldType) {
  static_assert(DescriptorField > 0 && DescriptorField < 10);
  mlir::Type previousFieldType =
      getDescFieldTypeModel<DescriptorField - 1>()(context);
  std::uint64_t previousOffset =
      getComponentOffset<DescriptorField - 1>(dl, context, previousFieldType);
  std::uint64_t offset = previousOffset + dl.getTypeSize(previousFieldType);
  std::uint64_t fieldAlignment = dl.getTypeABIAlignment(llvmFieldType);
  return llvm::alignTo(offset, fieldAlignment);
}
template <>
std::uint64_t getComponentOffset<0>(const mlir::DataLayout &dl,
                                    mlir::MLIRContext *context,
                                    mlir::Type llvmFieldType) {
  return 0;
}

DebugTypeGenerator::DebugTypeGenerator(mlir::ModuleOp m)
    : module(m), kindMapping(getKindMapping(m)) {
  LLVM_DEBUG(llvm::dbgs() << "DITypeAttr generator\n");

  std::optional<mlir::DataLayout> dl =
      fir::support::getOrSetDataLayout(module, /*allowDefaultLayout=*/true);
  if (!dl) {
    mlir::emitError(module.getLoc(), "Missing data layout attribute in module");
    return;
  }

  mlir::MLIRContext *context = module.getContext();

  // The debug information requires the offset of certain fields in the
  // descriptors like lower_bound and extent for each dimension.
  mlir::Type llvmDimsType = getDescFieldTypeModel<kDimsPosInBox>()(context);
  mlir::Type llvmPtrType = getDescFieldTypeModel<kAddrPosInBox>()(context);
  mlir::Type llvmLenType = getDescFieldTypeModel<kElemLenPosInBox>()(context);
  dimsOffset = getComponentOffset<kDimsPosInBox>(*dl, context, llvmDimsType);
  dimsSize = dl->getTypeSize(llvmDimsType);
  ptrSize = dl->getTypeSize(llvmPtrType);
  lenOffset = getComponentOffset<kElemLenPosInBox>(*dl, context, llvmLenType);
}

static mlir::LLVM::DITypeAttr genBasicType(mlir::MLIRContext *context,
                                           mlir::StringAttr name,
                                           unsigned bitSize,
                                           unsigned decoding) {
  return mlir::LLVM::DIBasicTypeAttr::get(
      context, llvm::dwarf::DW_TAG_base_type, name, bitSize, decoding);
}

static mlir::LLVM::DITypeAttr genPlaceholderType(mlir::MLIRContext *context) {
  return genBasicType(context, mlir::StringAttr::get(context, "integer"),
                      /*bitSize=*/32, llvm::dwarf::DW_ATE_signed);
}

mlir::LLVM::DITypeAttr DebugTypeGenerator::convertBoxedSequenceType(
    fir::SequenceType seqTy, mlir::LLVM::DIFileAttr fileAttr,
    mlir::LLVM::DIScopeAttr scope, mlir::Location loc, bool genAllocated,
    bool genAssociated) {

  mlir::MLIRContext *context = module.getContext();
  // FIXME: Assumed rank arrays not supported yet
  if (seqTy.hasUnknownShape())
    return genPlaceholderType(context);

  llvm::SmallVector<mlir::LLVM::DIExpressionElemAttr> ops;
  auto addOp = [&](unsigned opc, llvm::ArrayRef<uint64_t> vals) {
    ops.push_back(mlir::LLVM::DIExpressionElemAttr::get(context, opc, vals));
  };

  addOp(llvm::dwarf::DW_OP_push_object_address, {});
  addOp(llvm::dwarf::DW_OP_deref, {});

  // dataLocation = *base_addr
  mlir::LLVM::DIExpressionAttr dataLocation =
      mlir::LLVM::DIExpressionAttr::get(context, ops);
  addOp(llvm::dwarf::DW_OP_lit0, {});
  addOp(llvm::dwarf::DW_OP_ne, {});

  // allocated = associated = (*base_addr != 0)
  mlir::LLVM::DIExpressionAttr valid =
      mlir::LLVM::DIExpressionAttr::get(context, ops);
  mlir::LLVM::DIExpressionAttr allocated = genAllocated ? valid : nullptr;
  mlir::LLVM::DIExpressionAttr associated = genAssociated ? valid : nullptr;
  ops.clear();

  llvm::SmallVector<mlir::LLVM::DINodeAttr> elements;
  mlir::LLVM::DITypeAttr elemTy =
      convertType(seqTy.getEleTy(), fileAttr, scope, loc);
  unsigned offset = dimsOffset;
  const unsigned indexSize = dimsSize / 3;
  for ([[maybe_unused]] auto _ : seqTy.getShape()) {
    // For each dimension, find the offset of count and lower bound in the
    // descriptor and generate the dwarf expression to extract it.
    // FIXME: If `indexSize` happens to be bigger than address size on the
    // system then we may have to change 'DW_OP_deref' here.
    addOp(llvm::dwarf::DW_OP_push_object_address, {});
    addOp(llvm::dwarf::DW_OP_plus_uconst,
          {offset + (indexSize * kDimExtentPos)});
    addOp(llvm::dwarf::DW_OP_deref, {});
    // count[i] = *(base_addr + offset + (indexSize * kDimExtentPos))
    // where 'offset' is dimsOffset + (i * dimsSize)
    mlir::LLVM::DIExpressionAttr countAttr =
        mlir::LLVM::DIExpressionAttr::get(context, ops);
    ops.clear();

    addOp(llvm::dwarf::DW_OP_push_object_address, {});
    addOp(llvm::dwarf::DW_OP_plus_uconst,
          {offset + (indexSize * kDimLowerBoundPos)});
    addOp(llvm::dwarf::DW_OP_deref, {});
    // lower_bound[i] = *(base_addr + offset + (indexSize * kDimLowerBoundPos))
    mlir::LLVM::DIExpressionAttr lowerAttr =
        mlir::LLVM::DIExpressionAttr::get(context, ops);
    ops.clear();

    offset += dimsSize;
    mlir::LLVM::DISubrangeAttr subrangeTy = mlir::LLVM::DISubrangeAttr::get(
        context, countAttr, lowerAttr, /*upperBound=*/nullptr,
        /*stride=*/nullptr);
    elements.push_back(subrangeTy);
  }
  return mlir::LLVM::DICompositeTypeAttr::get(
      context, llvm::dwarf::DW_TAG_array_type, /*recursive_id=*/{},
      /*name=*/nullptr, /*file=*/nullptr, /*line=*/0, /*scope=*/nullptr, elemTy,
      mlir::LLVM::DIFlags::Zero, /*sizeInBits=*/0, /*alignInBits=*/0, elements,
      dataLocation, /*rank=*/nullptr, allocated, associated);
}

mlir::LLVM::DITypeAttr DebugTypeGenerator::convertSequenceType(
    fir::SequenceType seqTy, mlir::LLVM::DIFileAttr fileAttr,
    mlir::LLVM::DIScopeAttr scope, mlir::Location loc) {
  mlir::MLIRContext *context = module.getContext();

  llvm::SmallVector<mlir::LLVM::DINodeAttr> elements;
  mlir::LLVM::DITypeAttr elemTy =
      convertType(seqTy.getEleTy(), fileAttr, scope, loc);

  for (fir::SequenceType::Extent dim : seqTy.getShape()) {
    if (dim == seqTy.getUnknownExtent()) {
      // FIXME: This path is taken for assumed size arrays but also for arrays
      // with non constant extent. For the latter case, the DISubrangeAttr
      // should point to a variable which will have the extent at runtime.
      auto subrangeTy = mlir::LLVM::DISubrangeAttr::get(
          context, /*count=*/nullptr, /*lowerBound=*/nullptr,
          /*upperBound*/ nullptr, /*stride*/ nullptr);
      elements.push_back(subrangeTy);
    } else {
      auto intTy = mlir::IntegerType::get(context, 64);
      // FIXME: Only supporting lower bound of 1 at the moment. The
      // 'SequenceType' has information about the shape but not the shift. In
      // cases where the conversion originated during the processing of
      // 'DeclareOp', it may be possible to pass on this information. But the
      // type conversion should ideally be based on what information present in
      // the type class so that it works from everywhere (e.g. when it is part
      // of a module or a derived type.)
      auto countAttr = mlir::IntegerAttr::get(intTy, llvm::APInt(64, dim));
      auto lowerAttr = mlir::IntegerAttr::get(intTy, llvm::APInt(64, 1));
      auto subrangeTy = mlir::LLVM::DISubrangeAttr::get(
          context, countAttr, lowerAttr, /*upperBound=*/nullptr,
          /*stride=*/nullptr);
      elements.push_back(subrangeTy);
    }
  }
  // Apart from arrays, the `DICompositeTypeAttr` is used for other things like
  // structure types. Many of its fields which are not applicable to arrays
  // have been set to some valid default values.

  return mlir::LLVM::DICompositeTypeAttr::get(
      context, llvm::dwarf::DW_TAG_array_type, /*recursive_id=*/{},
      /*name=*/nullptr, /*file=*/nullptr, /*line=*/0, /*scope=*/nullptr, elemTy,
      mlir::LLVM::DIFlags::Zero, /*sizeInBits=*/0, /*alignInBits=*/0, elements,
      /*dataLocation=*/nullptr, /*rank=*/nullptr, /*allocated=*/nullptr,
      /*associated=*/nullptr);
}

mlir::LLVM::DITypeAttr DebugTypeGenerator::convertCharacterType(
    fir::CharacterType charTy, mlir::LLVM::DIFileAttr fileAttr,
    mlir::LLVM::DIScopeAttr scope, mlir::Location loc, bool hasDescriptor) {
  mlir::MLIRContext *context = module.getContext();

  // DWARF 5 says the following about the character encoding in 5.1.1.2.
  // "DW_ATE_ASCII and DW_ATE_UCS specify encodings for the Fortran 2003
  // string kinds ASCII (ISO/IEC 646:1991) and ISO_10646 (UCS-4 in ISO/IEC
  // 10646:2000)."
  unsigned encoding = llvm::dwarf::DW_ATE_ASCII;
  if (charTy.getFKind() != 1)
    encoding = llvm::dwarf::DW_ATE_UCS;

  uint64_t sizeInBits = 0;
  mlir::LLVM::DIExpressionAttr lenExpr = nullptr;
  mlir::LLVM::DIExpressionAttr locExpr = nullptr;

  if (hasDescriptor) {
    llvm::SmallVector<mlir::LLVM::DIExpressionElemAttr> ops;
    auto addOp = [&](unsigned opc, llvm::ArrayRef<uint64_t> vals) {
      ops.push_back(mlir::LLVM::DIExpressionElemAttr::get(context, opc, vals));
    };
    addOp(llvm::dwarf::DW_OP_push_object_address, {});
    addOp(llvm::dwarf::DW_OP_plus_uconst, {lenOffset});
    lenExpr = mlir::LLVM::DIExpressionAttr::get(context, ops);
    ops.clear();

    addOp(llvm::dwarf::DW_OP_push_object_address, {});
    addOp(llvm::dwarf::DW_OP_deref, {});
    locExpr = mlir::LLVM::DIExpressionAttr::get(context, ops);
  } else if (charTy.hasConstantLen()) {
    sizeInBits =
        charTy.getLen() * kindMapping.getCharacterBitsize(charTy.getFKind());
  } else {
    return genPlaceholderType(context);
  }

  // FIXME: Currently the DIStringType in llvm does not have the option to set
  // type of the underlying character. This restricts out ability to represent
  // string with non-default characters. Please see issue #95440 for more
  // details.
  return mlir::LLVM::DIStringTypeAttr::get(
      context, llvm::dwarf::DW_TAG_string_type,
      mlir::StringAttr::get(context, ""), sizeInBits, /*alignInBits=*/0,
      /*stringLength=*/nullptr, lenExpr, locExpr, encoding);
}

mlir::LLVM::DITypeAttr DebugTypeGenerator::convertPointerLikeType(
    mlir::Type elTy, mlir::LLVM::DIFileAttr fileAttr,
    mlir::LLVM::DIScopeAttr scope, mlir::Location loc, bool genAllocated,
    bool genAssociated) {
  mlir::MLIRContext *context = module.getContext();

  // Arrays and character need different treatment because DWARF have special
  // constructs for them to get the location from the descriptor. Rest of
  // types are handled like pointer to underlying type.
  if (auto seqTy = mlir::dyn_cast_or_null<fir::SequenceType>(elTy))
    return convertBoxedSequenceType(seqTy, fileAttr, scope, loc, genAllocated,
                                    genAssociated);
  if (auto charTy = mlir::dyn_cast_or_null<fir::CharacterType>(elTy))
    return convertCharacterType(charTy, fileAttr, scope, loc,
                                /*hasDescriptor=*/true);

  mlir::LLVM::DITypeAttr elTyAttr = convertType(elTy, fileAttr, scope, loc);

  return mlir::LLVM::DIDerivedTypeAttr::get(
      context, llvm::dwarf::DW_TAG_pointer_type,
      mlir::StringAttr::get(context, ""), elTyAttr, ptrSize,
      /*alignInBits=*/0, /*offset=*/0,
      /*optional<address space>=*/std::nullopt, /*extra data=*/nullptr);
}

mlir::LLVM::DITypeAttr
DebugTypeGenerator::convertType(mlir::Type Ty, mlir::LLVM::DIFileAttr fileAttr,
                                mlir::LLVM::DIScopeAttr scope,
                                mlir::Location loc) {
  mlir::MLIRContext *context = module.getContext();
  if (Ty.isInteger()) {
    return genBasicType(context, mlir::StringAttr::get(context, "integer"),
                        Ty.getIntOrFloatBitWidth(), llvm::dwarf::DW_ATE_signed);
  } else if (mlir::isa<mlir::FloatType>(Ty)) {
    return genBasicType(context, mlir::StringAttr::get(context, "real"),
                        Ty.getIntOrFloatBitWidth(), llvm::dwarf::DW_ATE_float);
  } else if (auto realTy = mlir::dyn_cast_or_null<fir::RealType>(Ty)) {
    return genBasicType(context, mlir::StringAttr::get(context, "real"),
                        kindMapping.getRealBitsize(realTy.getFKind()),
                        llvm::dwarf::DW_ATE_float);
  } else if (auto logTy = mlir::dyn_cast_or_null<fir::LogicalType>(Ty)) {
    return genBasicType(context,
                        mlir::StringAttr::get(context, logTy.getMnemonic()),
                        kindMapping.getLogicalBitsize(logTy.getFKind()),
                        llvm::dwarf::DW_ATE_boolean);
  } else if (fir::isa_complex(Ty)) {
    unsigned bitWidth;
    if (auto cplxTy = mlir::dyn_cast_or_null<mlir::ComplexType>(Ty)) {
      auto floatTy = mlir::cast<mlir::FloatType>(cplxTy.getElementType());
      bitWidth = floatTy.getWidth();
    } else if (auto cplxTy = mlir::dyn_cast_or_null<fir::ComplexType>(Ty)) {
      bitWidth = kindMapping.getRealBitsize(cplxTy.getFKind());
    } else {
      llvm_unreachable("Unhandled complex type");
    }
    return genBasicType(context, mlir::StringAttr::get(context, "complex"),
                        bitWidth * 2, llvm::dwarf::DW_ATE_complex_float);
  } else if (auto seqTy = mlir::dyn_cast_or_null<fir::SequenceType>(Ty)) {
    return convertSequenceType(seqTy, fileAttr, scope, loc);
  } else if (auto charTy = mlir::dyn_cast_or_null<fir::CharacterType>(Ty)) {
    return convertCharacterType(charTy, fileAttr, scope, loc,
                                /*hasDescriptor=*/false);
  } else if (auto boxTy = mlir::dyn_cast_or_null<fir::BoxType>(Ty)) {
    auto elTy = boxTy.getElementType();
    if (auto seqTy = mlir::dyn_cast_or_null<fir::SequenceType>(elTy))
      return convertBoxedSequenceType(seqTy, fileAttr, scope, loc, false,
                                      false);
    if (auto heapTy = mlir::dyn_cast_or_null<fir::HeapType>(elTy))
      return convertPointerLikeType(heapTy.getElementType(), fileAttr, scope,
                                    loc, /*genAllocated=*/true,
                                    /*genAssociated=*/false);
    if (auto ptrTy = mlir::dyn_cast_or_null<fir::PointerType>(elTy))
      return convertPointerLikeType(ptrTy.getElementType(), fileAttr, scope,
                                    loc, /*genAllocated=*/false,
                                    /*genAssociated=*/true);
    return genPlaceholderType(context);
  } else {
    // FIXME: These types are currently unhandled. We are generating a
    // placeholder type to allow us to test supported bits.
    return genPlaceholderType(context);
  }
}

} // namespace fir
