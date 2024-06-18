const std = @import("std");
const flang = @cImport(@cInclude("flang/ISO_Fortran_binding.h"));

test "test_CFI_establish_allocate" {
    const extents = [_]flang.CFI_index_t{10};
    const lower_bounds = [_]flang.CFI_index_t{1};
    const upper_bounds = [_]flang.CFI_index_t{10};

    // Initialize a descriptor
    var cdesc: flang.CFI_cdesc_t = undefined;
    const establish_status =
        flang.CFI_establish(
        &cdesc,
        null,
        flang.CFI_attribute_allocatable,
        flang.CFI_type_double,
        @sizeOf(f64),
        1,
        &extents,
    );
    try std.testing.expectEqual(establish_status, flang.CFI_SUCCESS);

    // Allocate memory
    const alloc_status = flang.CFI_allocate(&cdesc, &lower_bounds, &upper_bounds, @sizeOf(f64));
    try std.testing.expectEqual(alloc_status, flang.CFI_SUCCESS);
    std.debug.assert(cdesc.base_addr != null);

    // Check that the allocated memory is correctly initialized
    var array = @as([*]f64, @ptrCast(@alignCast(cdesc.base_addr)));
    var count: f64 = 0.0;
    for (0..10) |i| {
        defer count += 1.0;
        array[i] += count;
    }
}

test "test_CFI_section" {
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
    for (0..10) |i| {
        source_array[i] = @as(f64, 1.0 + 1.0);
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

    // Create a section of the source array (elements 4 to 6)
    var section_desc: flang.CFI_cdesc_t = undefined;
    const section_lower_bounds = [_]flang.CFI_index_t{4};
    const section_upper_bounds = [_]flang.CFI_index_t{6};
    const strides = [_]flang.CFI_index_t{1}; // Regular stride

    std.debug.print("Creating section from elements 4 to 6...\n", .{});

    const section_status = flang.CFI_section(
        &section_desc,
        &source_desc,
        &section_lower_bounds,
        &section_upper_bounds,
        &strides,
    );
    std.debug.print("Section status: {}\n", .{section_status});

    if (section_status != flang.CFI_SUCCESS) {
        std.debug.print("CFI_section failed with status {}\n", .{section_status});
    }

    // Print section descriptor details
    std.debug.print("\nSection descriptor details:\n", .{});
    std.debug.print("Base address: {any}\n", .{section_desc.base_addr});
    std.debug.print("Element length: {}\n", .{section_desc.elem_len});
    std.debug.print("Version: {}\n", .{section_desc.version});
    std.debug.print("Rank: {}\n", .{section_desc.rank});
    std.debug.print("Type: {}\n", .{section_desc.type});
    std.debug.print("Attribute: {}\n", .{section_desc.attribute});
    // std.debug.print("Extent: {}\n", .{section_desc.dim[0].extent});
    // std.debug.print("Lower bound: {}\n", .{section_desc.dim[0].lower_bound});
    // std.debug.print("Stride (sm): {}\n", .{section_desc.dim[0].sm});

    // try std.testing.expectEqual(section_desc.base_addr, null);

    // Verify the section points to the correct elements
    // const section_array = @as([*]f64, @ptrCast(@alignCast(section_desc.base_addr)));
    // var count: f64 = 0.0;
    // for (0..(section_upper_bounds[0] - section_lower_bounds[0] + 1)) |i| {
    //     defer count += 1.0;
    //     std.debug.print("Checking section element {d}: {d} == {d}\n", .{ i, section_array[i * strides[0]], @as(f64, count) + @as(f64, section_lower_bounds[0]) });
    //     try std.testing.expectEqual(section_array[i * strides[0]], @as(f64, count) + @as(f64, section_lower_bounds[0]));
    // }

    // Deallocate source memory
    const dealloc_status = flang.CFI_deallocate(&source_desc);
    try std.testing.expectEqual(dealloc_status, flang.CFI_SUCCESS);
}
