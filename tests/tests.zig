const std = @import("std");
const flang = @cImport(@cInclude("flang/ISO_Fortran_binding.h"));

test "test_CFI_establish_allocate" {
    const extents = [_]flang.CFI_index_t{10};
    const lower_bounds = [_]flang.CFI_index_t{1};
    const upper_bounds = [_]flang.CFI_index_t{10};

    // Initialize a descriptor
    var source_desc: flang.CFI_cdesc_t = undefined;
    const establish_status = flang.CFI_establish(
        &source_desc,
        null,
        flang.CFI_attribute_allocatable,
        flang.CFI_type_double,
        @sizeOf(f64),
        1,
        &extents,
    );
    try std.testing.expectEqual(establish_status, flang.CFI_SUCCESS);

    // Allocate memory
    const alloc_status = flang.CFI_allocate(&source_desc, &lower_bounds, &upper_bounds, @sizeOf(f64));
    try std.testing.expectEqual(alloc_status, flang.CFI_SUCCESS);

    // Initialize the array
    var source_array = @as([*]f64, @ptrCast(@alignCast(source_desc.base_addr)));
    var count: f64 = 0.0;
    for (0..10) |i| {
        defer count += 1.0;
        source_array[i] = @as(f64, count + 1.0);
    }

    // Print source descriptor details
    std.debug.print("Source descriptor details:\n", .{});
    std.debug.print("Base address: {any}\n", .{source_desc.base_addr});
    std.debug.print("Element length: {}\n", .{source_desc.elem_len});
    std.debug.print("Version: {}\n", .{source_desc.version});
    std.debug.print("Rank: {}\n", .{source_desc.rank});
    std.debug.print("Type: {}\n", .{source_desc.type});
    std.debug.print("Attribute: {}\n", .{source_desc.attribute});
    // std.debug.print("Extent: {}\n", .{source_desc.dim[0].extent});
    // std.debug.print("Lower bound: {}\n", .{source_desc.dim[0].lower_bound});
    // std.debug.print("Stride (sm): {}\n", .{source_desc.dim[0].sm});

    // Deallocate source memory
    const dealloc_status = flang.CFI_deallocate(&source_desc);
    try std.testing.expectEqual(dealloc_status, flang.CFI_SUCCESS);

    try std.testing.expectEqual(null, source_desc.base_addr);
}
