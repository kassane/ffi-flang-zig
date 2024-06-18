#include <cstdint>
#include <flang/ISO_Fortran_binding_wrapper.h>
#include <iostream>

using namespace Fortran::ISO;

void test_scalar() {
  float x = 3.14f;
  float y;

  // Create descriptor for scalar x
  CFI_cdesc_t x_desc;
  x_desc.base_addr = &x;
  x_desc.elem_len = sizeof(float);
  x_desc.version = CFI_VERSION;
  x_desc.rank = 0;
  x_desc.attribute = CFI_attribute_other;
  x_desc.type = CFI_type_float;

  void *x_addr = CFI_address(&x_desc, nullptr);
  std::cout << "Address of x: " << x_addr << std::endl;

  // Create descriptor for scalar y
  CFI_cdesc_t y_desc;
  y_desc.base_addr = &y;
  y_desc.elem_len = sizeof(float);
  y_desc.version = CFI_VERSION;
  y_desc.rank = 0;
  y_desc.attribute = CFI_attribute_other;
  y_desc.type = CFI_type_float;

  void *y_addr = CFI_address(&y_desc, nullptr);
  std::cout << "Address of y: " << y_addr << std::endl;
}

void test_array() {
  // Allocate 1D array of 10 floats
  CFI_index_t extent = 10;
  CFI_cdesc_t array_desc;
  array_desc.version = CFI_VERSION;
  array_desc.rank = 1;
  array_desc.attribute = CFI_attribute_allocatable;
  array_desc.type = CFI_type_float;

  int status = CFI_allocate(&array_desc, nullptr, &extent, sizeof(float));
  if (status != CFI_SUCCESS) {
    std::cerr << "CFI_allocate failed with status: " << status << std::endl;
    return;
  }

  float *float_array = reinterpret_cast<float *>(array_desc.base_addr);
  // Initialize array...
  for (int i = 0; i < 10; ++i) {
    float_array[i] = i * 1.0f;
  }

  // Use array...
  std::cout << "Array elements: ";
  for (int i = 0; i < 10; ++i) {
    std::cout << float_array[i] << " ";
  }
  std::cout << std::endl;

  // Deallocate array
  status = CFI_deallocate(&array_desc);
  if (status != CFI_SUCCESS) {
    std::cerr << "CFI_deallocate failed with status: " << status << std::endl;
  }
}

int main() {
  test_scalar();
  test_array();
  return 0;
}
