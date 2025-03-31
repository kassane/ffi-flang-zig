const std = @import("std");

const flang_version: std.SemanticVersion = .{
    .major = 19,
    .minor = 1,
    .patch = 7,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const shared = b.option(bool, "shared", "Build as shared library [default: false]") orelse false;
    const amalgamation = b.option(bool, "amalgamation", "Build as amalgamation [default: false]") orelse false;
    const tests = b.option(bool, "enable-tests", "Build tests [default: false]") orelse false;

    const libDec = buildFortranDecimal(b, .{
        .target = target,
        .optimize = optimize,
        .is_shared = shared,
    });
    const libRuntime = buildFortranRuntime(b, .{
        .target = target,
        .optimize = optimize,
        .is_shared = shared,
    });

    if (amalgamation) {
        libRuntime.linkLibrary(libDec);
    } else {
        b.installArtifact(libDec);
    }
    b.installArtifact(libRuntime);

    // avoid duplicate main symbol
    if (tests and amalgamation) {
        const exe = buildTest(b, exeInfo{
            .target = target,
            .optimize = optimize,
            .lib = libRuntime,
        });

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step(exe.name, b.fmt("Run {s}", .{exe.name}));
        run_step.dependOn(&run_cmd.step);
    }
}

const libConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    is_shared: bool = false,
};

fn buildFortranRuntime(b: *std.Build, options: libConfig) *std.Build.Step.Compile {
    const libfortran = if (options.is_shared) b.addSharedLibrary(.{
        .name = "FortranRuntime",
        .target = options.target,
        .optimize = options.optimize,
        .version = flang_version,
    }) else b.addStaticLibrary(.{
        .name = "FortranRuntime",
        .target = options.target,
        .optimize = options.optimize,
        .version = flang_version,
    });
    libfortran.root_module.addIncludePath(b.path("include"));
    libfortran.root_module.addCSourceFiles(.{
        .files = runtime,
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-std=c++17",
        },
    });

    switch (libfortran.rootModuleTarget().cpu.arch.endian()) {
        .big => libfortran.root_module.addCMacro("FLANG_BIG_ENDIAN", "1"),
        .little => libfortran.root_module.addCMacro("FLANG_LITTLE_ENDIAN", "1"),
    }

    if (libfortran.rootModuleTarget().abi != .msvc)
        libfortran.linkLibCpp()
    else {
        libfortran.root_module.addCMacro("_CRT_SECURE_NO_WARNINGS", "");
        libfortran.linkLibC();
    }
    libfortran.installHeadersDirectory(b.path("include"), "", .{
        .exclude_extensions = &.{
            "clang-format",
            "clang-tidy",
            "inc",
            "def",
        },
    });
    return libfortran;
}

fn buildFortranDecimal(b: *std.Build, options: libConfig) *std.Build.Step.Compile {
    const libdecimal = if (options.is_shared) b.addSharedLibrary(.{
        .name = "FortranDecimal",
        .target = options.target,
        .optimize = options.optimize,
        .version = flang_version,
    }) else b.addStaticLibrary(.{
        .name = "FortranDecimal",
        .target = options.target,
        .optimize = options.optimize,
        .version = flang_version,
    });
    libdecimal.root_module.addIncludePath(b.path("include"));
    libdecimal.root_module.addCSourceFiles(.{
        .files = lib_decimal,
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-std=c++17",
        },
    });
    switch (libdecimal.rootModuleTarget().cpu.arch.endian()) {
        .big => libdecimal.root_module.addCMacro("FLANG_BIG_ENDIAN", "1"),
        .little => libdecimal.root_module.addCMacro("FLANG_LITTLE_ENDIAN", "1"),
    }
    if (libdecimal.rootModuleTarget().abi != .msvc)
        libdecimal.linkLibCpp()
    else {
        libdecimal.root_module.addCMacro("_CRT_SECURE_NO_WARNINGS", "");
        libdecimal.linkLibC();
    }
    return libdecimal;
}

// -----------------------------------------------------------------------------

const exeInfo = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib: *std.Build.Step.Compile,
};

fn buildTest(b: *std.Build, options: exeInfo) *std.Build.Step.Compile {
    const exe = b.addTest(.{
        .root_source_file = b.path("tests/tests.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    switch (exe.rootModuleTarget().cpu.arch.endian()) {
        .big => exe.root_module.addCMacro("FLANG_BIG_ENDIAN", "1"),
        .little => exe.root_module.addCMacro("FLANG_LITTLE_ENDIAN", "1"),
    }
    for (options.lib.root_module.include_dirs.items) |dir| {
        if (dir == .other_step) continue;
        exe.root_module.addIncludePath(dir.path);
    }
    exe.linkLibrary(options.lib);
    if (exe.rootModuleTarget().abi != .msvc)
        exe.linkLibCpp()
    else {
        exe.root_module.addCMacro("_CRT_SECURE_NO_WARNINGS", "");
        exe.linkLibC();
    }
    return exe;
}

const runtime = &.{
    "src/runtime/ISO_Fortran_binding.cpp",
    "src/runtime/allocatable.cpp",
    "src/runtime/array-constructor.cpp",
    "src/runtime/assign.cpp",
    "src/runtime/buffer.cpp",
    "src/runtime/character.cpp",
    "src/runtime/command.cpp",
    "src/runtime/complex-powi.cpp",
    "src/runtime/connection.cpp",
    "src/runtime/copy.cpp",
    "src/runtime/derived-api.cpp",
    "src/runtime/derived.cpp",
    "src/runtime/descriptor-io.cpp",
    "src/runtime/descriptor.cpp",
    "src/runtime/dot-product.cpp",
    "src/runtime/edit-input.cpp",
    "src/runtime/edit-output.cpp",
    "src/runtime/environment.cpp",
    "src/runtime/exceptions.cpp",
    "src/runtime/execute.cpp",
    "src/runtime/extensions.cpp",
    "src/runtime/extrema.cpp",
    "src/runtime/external-unit.cpp",
    "src/runtime/file.cpp",
    "src/runtime/findloc.cpp",
    "src/runtime/format.cpp",
    "src/runtime/inquiry.cpp",
    "src/runtime/internal-unit.cpp",
    "src/runtime/io-api.cpp",
    "src/runtime/io-api-minimal.cpp",
    "src/runtime/io-error.cpp",
    "src/runtime/io-stmt.cpp",
    "src/runtime/iostat.cpp",
    "src/runtime/main.cpp",
    "src/runtime/matmul-transpose.cpp",
    "src/runtime/matmul.cpp",
    "src/runtime/memory.cpp",
    "src/runtime/misc-intrinsic.cpp",
    "src/runtime/namelist.cpp",
    "src/runtime/non-tbp-dio.cpp",
    "src/runtime/numeric.cpp",
    "src/runtime/pointer.cpp",
    "src/runtime/product.cpp",
    "src/runtime/pseudo-unit.cpp",
    "src/runtime/ragged.cpp",
    "src/runtime/random.cpp",
    "src/runtime/reduce.cpp",
    "src/runtime/reduction.cpp",
    "src/runtime/stat.cpp",
    "src/runtime/stop.cpp",
    "src/runtime/sum.cpp",
    "src/runtime/support.cpp",
    "src/runtime/temporary-stack.cpp",
    "src/runtime/terminator.cpp",
    "src/runtime/time-intrinsic.cpp",
    "src/runtime/tools.cpp",
    "src/runtime/transformational.cpp",
    "src/runtime/type-code.cpp",
    "src/runtime/type-info.cpp",
    "src/runtime/unit-map.cpp",
    "src/runtime/unit.cpp",
    "src/runtime/utf.cpp",
};

const lib_decimal = &.{
    "src/lib/Decimal/binary-to-decimal.cpp",
    "src/lib/Decimal/decimal-to-binary.cpp",
};

// ----------------------------------------------------------------------------
// Need LLVM-APIs
// ----------------------------------------------------------------------------
// const lib_common = &.{
//     "src/lib/Common/Fortran-features.cpp",
//     "src/lib/Common/Fortran.cpp",
//     "src/lib/Common/Version.cpp",
//     "src/lib/Common/default-kinds.cpp",
//     "src/lib/Common/idioms.cpp",
// };

// const lib_eval = &.{
//     "src/lib/Evaluate/call.cpp",
//     "src/lib/Evaluate/characteristics.cpp",
//     "src/lib/Evaluate/check-expression.cpp",
//     "src/lib/Evaluate/common.cpp",
//     "src/lib/Evaluate/complex.cpp",
//     "src/lib/Evaluate/constant.cpp",
//     "src/lib/Evaluate/expression.cpp",
//     "src/lib/Evaluate/fold-character.cpp",
//     "src/lib/Evaluate/fold-complex.cpp",
//     "src/lib/Evaluate/fold-designator.cpp",
//     "src/lib/Evaluate/fold-integer.cpp",
//     "src/lib/Evaluate/fold-logical.cpp",
//     "src/lib/Evaluate/fold-real.cpp",
//     "src/lib/Evaluate/fold-reduction.cpp",
//     "src/lib/Evaluate/fold.cpp",
//     "src/lib/Evaluate/formatting.cpp",
//     "src/lib/Evaluate/host.cpp",
//     "src/lib/Evaluate/initial-image.cpp",
//     "src/lib/Evaluate/integer.cpp",
//     "src/lib/Evaluate/intrinsics-library.cpp",
//     "src/lib/Evaluate/intrinsics.cpp",
//     "src/lib/Evaluate/logical.cpp",
//     "src/lib/Evaluate/real.cpp",
//     "src/lib/Evaluate/shape.cpp",
//     "src/lib/Evaluate/static-data.cpp",
//     "src/lib/Evaluate/target.cpp",
//     "src/lib/Evaluate/tools.cpp",
//     "src/lib/Evaluate/type.cpp",
//     "src/lib/Evaluate/variable.cpp",
// };

// const lib_frontend_parser = &.{
//     "src/lib/Frontend/CodeGenOptions.cpp",
//     "src/lib/Frontend/CompilerInstance.cpp",
//     "src/lib/Frontend/CompilerInvocation.cpp",
//     "src/lib/Frontend/FrontendAction.cpp",
//     "src/lib/Frontend/FrontendActions.cpp",
//     "src/lib/Frontend/FrontendOptions.cpp",
//     "src/lib/Frontend/LangOptions.cpp",
//     "src/lib/Frontend/TextDiagnostic.cpp",
//     "src/lib/Frontend/TextDiagnosticBuffer.cpp",
//     "src/lib/Frontend/TextDiagnosticPrinter.cpp",
//     "src/lib/FrontendTool/ExecuteCompilerInvocation.cpp",
//     "src/lib/Lower/Allocatable.cpp",
//     "src/lib/Lower/Bridge.cpp",
//     "src/lib/Lower/CallInterface.cpp",
//     "src/lib/Lower/Coarray.cpp",
//     "src/lib/Lower/ComponentPath.cpp",
//     "src/lib/Lower/ConvertArrayConstructor.cpp",
//     "src/lib/Lower/ConvertCall.cpp",
//     "src/lib/Lower/ConvertConstant.cpp",
//     "src/lib/Lower/ConvertExpr.cpp",
//     "src/lib/Lower/ConvertExprToHLFIR.cpp",
//     "src/lib/Lower/ConvertProcedureDesignator.cpp",
//     "src/lib/Lower/ConvertType.cpp",
//     "src/lib/Lower/ConvertVariable.cpp",
//     "src/lib/Lower/CustomIntrinsicCall.cpp",
//     "src/lib/Lower/DumpEvaluateExpr.cpp",
//     "src/lib/Lower/HlfirIntrinsics.cpp",
//     "src/lib/Lower/HostAssociations.cpp",
//     "src/lib/Lower/IO.cpp",
//     "src/lib/Lower/IterationSpace.cpp",
//     "src/lib/Lower/LoweringOptions.cpp",
//     "src/lib/Lower/Mangler.cpp",
//     "src/lib/Lower/OpenACC.cpp",
//     "src/lib/Lower/OpenMP.cpp",
//     "src/lib/Lower/PFTBuilder.cpp",
//     "src/lib/Lower/Runtime.cpp",
//     "src/lib/Lower/SymbolMap.cpp",
//     "src/lib/Lower/VectorSubscripts.cpp",
//     "src/lib/Optimizer/Analysis/AliasAnalysis.cpp",
//     "src/lib/Optimizer/Analysis/TBAAForest.cpp",
//     "src/lib/Optimizer/Builder/BoxValue.cpp",
//     "src/lib/Optimizer/Builder/Character.cpp",
//     "src/lib/Optimizer/Builder/Complex.cpp",
//     "src/lib/Optimizer/Builder/DoLoopHelper.cpp",
//     "src/lib/Optimizer/Builder/FIRBuilder.cpp",
//     "src/lib/Optimizer/Builder/HLFIRTools.cpp",
//     "src/lib/Optimizer/Builder/IntrinsicCall.cpp",
//     "src/lib/Optimizer/Builder/LowLevelIntrinsics.cpp",
//     "src/lib/Optimizer/Builder/MutableBox.cpp",
//     "src/lib/Optimizer/Builder/PPCIntrinsicCall.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Allocatable.cpp",
//     "src/lib/Optimizer/Builder/Runtime/ArrayConstructor.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Assign.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Character.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Command.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Derived.cpp",
//     "src/lib/Optimizer/Builder/Runtime/EnvironmentDefaults.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Exceptions.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Execute.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Inquiry.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Intrinsics.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Numeric.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Pointer.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Ragged.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Reduction.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Stop.cpp",
//     "src/lib/Optimizer/Builder/Runtime/TemporaryStack.cpp",
//     "src/lib/Optimizer/Builder/Runtime/Transformational.cpp",
//     "src/lib/Optimizer/Builder/TemporaryStorage.cpp",
//     "src/lib/Optimizer/CodeGen/BoxedProcedure.cpp",
//     "src/lib/Optimizer/CodeGen/CGOps.cpp",
//     "src/lib/Optimizer/CodeGen/CodeGen.cpp",
//     "src/lib/Optimizer/CodeGen/PreCGRewrite.cpp",
//     "src/lib/Optimizer/CodeGen/TBAABuilder.cpp",
//     "src/lib/Optimizer/CodeGen/Target.cpp",
//     "src/lib/Optimizer/CodeGen/TargetRewrite.cpp",
//     "src/lib/Optimizer/CodeGen/TypeConverter.cpp",
//     "src/lib/Optimizer/Dialect/FIRAttr.cpp",
//     "src/lib/Optimizer/Dialect/FIRDialect.cpp",
//     "src/lib/Optimizer/Dialect/FIROps.cpp",
//     "src/lib/Optimizer/Dialect/FIRType.cpp",
//     "src/lib/Optimizer/Dialect/FirAliasTagOpInterface.cpp",
//     "src/lib/Optimizer/Dialect/FortranVariableInterface.cpp",
//     "src/lib/Optimizer/Dialect/Inliner.cpp",
//     "src/lib/Optimizer/Dialect/Support/FIRContext.cpp",
//     "src/lib/Optimizer/Dialect/Support/KindMapping.cpp",
//     "src/lib/Optimizer/HLFIR/IR/HLFIRDialect.cpp",
//     "src/lib/Optimizer/HLFIR/IR/HLFIROps.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/BufferizeHLFIR.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/ConvertToFIR.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/InlineElementals.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/LowerHLFIRIntrinsics.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/LowerHLFIROrderedAssignments.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/OptimizedBufferization.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/ScheduleOrderedAssignments.cpp",
//     "src/lib/Optimizer/HLFIR/Transforms/SimplifyHLFIRIntrinsics.cpp",
//     "src/lib/Optimizer/Support/DataLayout.cpp",
//     "src/lib/Optimizer/Support/InitFIR.cpp",
//     "src/lib/Optimizer/Support/InternalNames.cpp",
//     "src/lib/Optimizer/Transforms/AbstractResult.cpp",
//     "src/lib/Optimizer/Transforms/AddAliasTags.cpp",
//     "src/lib/Optimizer/Transforms/AddDebugFoundation.cpp",
//     "src/lib/Optimizer/Transforms/AffineDemotion.cpp",
//     "src/lib/Optimizer/Transforms/AffinePromotion.cpp",
//     "src/lib/Optimizer/Transforms/AlgebraicSimplification.cpp",
//     "src/lib/Optimizer/Transforms/AnnotateConstant.cpp",
//     "src/lib/Optimizer/Transforms/ArrayValueCopy.cpp",
//     "src/lib/Optimizer/Transforms/CharacterConversion.cpp",
//     "src/lib/Optimizer/Transforms/ControlFlowConverter.cpp",
//     "src/lib/Optimizer/Transforms/ExternalNameConversion.cpp",
//     "src/lib/Optimizer/Transforms/FunctionAttr.cpp",
//     "src/lib/Optimizer/Transforms/LoopVersioning.cpp",
//     "src/lib/Optimizer/Transforms/MemRefDataFlowOpt.cpp",
//     "src/lib/Optimizer/Transforms/MemoryAllocation.cpp",
//     "src/lib/Optimizer/Transforms/OMPFunctionFiltering.cpp",
//     "src/lib/Optimizer/Transforms/OMPMarkDeclareTarget.cpp",
//     "src/lib/Optimizer/Transforms/PolymorphicOpConversion.cpp",
//     "src/lib/Optimizer/Transforms/SimplifyIntrinsics.cpp",
//     "src/lib/Optimizer/Transforms/SimplifyRegionLite.cpp",
//     "src/lib/Optimizer/Transforms/StackArrays.cpp",
//     "src/lib/Optimizer/Transforms/VScaleAttr.cpp",
//     "src/lib/Parser/Fortran-parsers.cpp",
//     "src/lib/Parser/char-block.cpp",
//     "src/lib/Parser/char-buffer.cpp",
//     "src/lib/Parser/char-set.cpp",
//     "src/lib/Parser/characters.cpp",
//     "src/lib/Parser/debug-parser.cpp",
//     "src/lib/Parser/executable-parsers.cpp",
//     "src/lib/Parser/expr-parsers.cpp",
//     "src/lib/Parser/instrumented-parser.cpp",
//     "src/lib/Parser/io-parsers.cpp",
//     "src/lib/Parser/message.cpp",
//     "src/lib/Parser/openacc-parsers.cpp",
//     "src/lib/Parser/openmp-parsers.cpp",
//     "src/lib/Parser/parse-tree.cpp",
//     "src/lib/Parser/parsing.cpp",
//     "src/lib/Parser/preprocessor.cpp",
//     "src/lib/Parser/prescan.cpp",
//     "src/lib/Parser/program-parsers.cpp",
//     "src/lib/Parser/provenance.cpp",
//     "src/lib/Parser/source.cpp",
//     "src/lib/Parser/token-sequence.cpp",
//     "src/lib/Parser/tools.cpp",
//     "src/lib/Parser/unparse.cpp",
//     "src/lib/Parser/user-state.cpp",
// };

// const semmantic = &.{
//     "src/lib/Semantics/assignment.cpp",
//     "src/lib/Semantics/attr.cpp",
//     "src/lib/Semantics/canonicalize-acc.cpp",
//     "src/lib/Semantics/canonicalize-do.cpp",
//     "src/lib/Semantics/canonicalize-omp.cpp",
//     "src/lib/Semantics/check-acc-structure.cpp",
//     "src/lib/Semantics/check-allocate.cpp",
//     "src/lib/Semantics/check-arithmeticif.cpp",
//     "src/lib/Semantics/check-call.cpp",
//     "src/lib/Semantics/check-case.cpp",
//     "src/lib/Semantics/check-coarray.cpp",
//     "src/lib/Semantics/check-cuda.cpp",
//     "src/lib/Semantics/check-data.cpp",
//     "src/lib/Semantics/check-deallocate.cpp",
//     "src/lib/Semantics/check-declarations.cpp",
//     "src/lib/Semantics/check-do-forall.cpp",
//     "src/lib/Semantics/check-if-stmt.cpp",
//     "src/lib/Semantics/check-io.cpp",
//     "src/lib/Semantics/check-namelist.cpp",
//     "src/lib/Semantics/check-nullify.cpp",
//     "src/lib/Semantics/check-omp-structure.cpp",
//     "src/lib/Semantics/check-purity.cpp",
//     "src/lib/Semantics/check-return.cpp",
//     "src/lib/Semantics/check-select-rank.cpp",
//     "src/lib/Semantics/check-select-type.cpp",
//     "src/lib/Semantics/check-stop.cpp",
//     "src/lib/Semantics/compute-offsets.cpp",
//     "src/lib/Semantics/data-to-inits.cpp",
//     "src/lib/Semantics/definable.cpp",
//     "src/lib/Semantics/expression.cpp",
//     "src/lib/Semantics/mod-file.cpp",
//     "src/lib/Semantics/pointer-assignment.cpp",
//     "src/lib/Semantics/program-tree.cpp",
//     "src/lib/Semantics/resolve-directives.cpp",
//     "src/lib/Semantics/resolve-labels.cpp",
//     "src/lib/Semantics/resolve-names-utils.cpp",
//     "src/lib/Semantics/resolve-names.cpp",
//     "src/lib/Semantics/rewrite-directives.cpp",
//     "src/lib/Semantics/rewrite-parse-tree.cpp",
//     "src/lib/Semantics/runtime-type-info.cpp",
//     "src/lib/Semantics/scope.cpp",
//     "src/lib/Semantics/semantics.cpp",
//     "src/lib/Semantics/symbol.cpp",
//     "src/lib/Semantics/tools.cpp",
//     "src/lib/Semantics/type.cpp",
//     "src/lib/Semantics/unparse-with-symbols.cpp",
// };
// ----------------------------------------------------------------------------
