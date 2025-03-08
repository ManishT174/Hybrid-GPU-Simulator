# matrix_multiply.asm
# Example matrix multiplication program for GPU simulator
#
# This program demonstrates a more complex GPGPU computation:
# Matrix multiplication C = A × B where:
# - A is an M×K matrix
# - B is a K×N matrix
# - C is the resulting M×N matrix
#
# The implementation uses a tiled approach with shared memory
# to improve memory access patterns and reduce global memory bandwidth

.data
    .align 4
# Matrix dimensions
matrix_dims:
    .word 64, 64, 64              # M = 64, K = 64, N = 64 (square matrices for simplicity)

# Input matrices (in row-major order)
matrix_a:
    .space 16384                  # Matrix A: 64×64 elements * 4 bytes = 16KB
matrix_b:
    .space 16384                  # Matrix B: 64×64 elements * 4 bytes = 16KB
    
# Output matrix
matrix_c:
    .space 16384                  # Matrix C: 64×64 elements * 4 bytes = 16KB

.shared
    .align 4
# Shared memory tiles for the computation
tile_a:
    .space 4096                   # Tile A: 32×32 elements * 4 bytes = 4KB
tile_b:
    .space 4096                   # Tile B: 32×32 elements * 4 bytes = 4KB

.text
.global main

main:
    # Initialize registers with matrix parameters
    addiu   $r1, $r0, matrix_dims
    ld.w    $r2, $r1, 0            # r2 = M (rows of A, rows of C)
    ld.w    $r3, $r1, 4            # r3 = K (cols of A, rows of B)
    ld.w    $r4, $r1, 8            # r4 = N (cols of B, cols of C)
    
    # Set matrix base addresses
    addiu   $r5, $r0, matrix_a     # r5 = base address of matrix A
    addiu   $r6, $r0, matrix_b     # r6 = base address of matrix B
    addiu   $r7, $r0, matrix_c     # r7 = base address of matrix C
    
    # Set tile base addresses
    addiu   $r8, $r0, tile_a       # r8 = base address of tile A in shared memory
    addiu   $r9, $r0, tile_b       # r9 = base address of tile B in shared memory
    
    # Define tile dimensions (TILE_SIZE)
    addiu   $r10, $r0, 32          # r10 = TILE_SIZE (32×32 tiles)
    
    # Get thread and block IDs
    tid     $r11                   # r11 = thread ID within block
    warpid  $r12                   # r12 = warp ID within block
    blockid $r13                   # r13 = block ID (assumed linearized)
    
    # Calculate block's starting position in the output matrix
    # Each block computes a TILE_SIZE×TILE_SIZE portion of C
    
    # Calculate block row and col indices
    div     $r14, $r13, $r4        # r14 = block_id / N (integer division for row)
    shl     $r14, $r14, 5          # r14 = r14 * 32 (block row * TILE_SIZE)
    
    rem     $r15, $r13, $r4        # r15 = block_id % N (remainder for column)
    shl     $r15, $r15, 5          # r15 = r15 * 32 (block col * TILE_SIZE)
    
    # Calculate thread's position within the tile
    div     $r16, $r11, $r10       # r16 = thread_id / TILE_SIZE (row within tile)
    rem     $r17, $r11, $r10       # r17 = thread_id % TILE_SIZE (col within tile)
    
    # Calculate thread's global position in output matrix C
    add     $r18, $r14, $r16       # r18 = blockRow + threadRow (global row)
    add     $r19, $r15, $r17       # r19 = blockCol + threadCol (global col)
    
    # Check if thread is within matrix bounds
    cmp     $r20, $r18, $r2        # r20 = (global_row < M) ? 1 : 0
    beq     $r20, $r0, exit_thread # If global_row >= M, exit
    
    cmp     $r21, $r19, $r4        # r21 = (global_col < N) ? 1 : 0
    beq     $r21, $r0, exit_thread # If global_col >= N, exit
    
    # Initialize accumulator for dot product
    addiu   $r22, $r0, 0           # r22 = 0 (accumulator for C[global_row][global_col])
    
    # Number of tiles needed to cover K dimension
    div     $r23, $r3, $r10        # r23 = K / TILE_SIZE
    rem     $r24, $r3, $r10        # r24 = K % TILE_SIZE
    bne     $r24, $r0, add_one_tile  # If remainder != 0, add one more tile
    j       start_loop
    
add_one_tile:
    addiu   $r23, $r23, 1          # One more tile needed for remaining elements
    
start_loop:
    # Initialize tile counter
    addiu   $r24, $r0, 0           # r24 = 0 (tile counter)
    
tile_loop:
    # Check if all tiles have been processed
    cmp     $r25, $r24, $r23       # r25 = (tile_counter < num_tiles) ? 1 : 0
    beq     $r25, $r0, loop_done
    
    # Calculate tile's starting position in A and B
    shl     $r26, $r24, 5          # r26 = tile_counter * TILE_SIZE
    
    # Load tiles from global to shared memory (cooperatively by all threads)
    # Each thread loads one element of each tile
    
    # Thread's load position in A
    mul     $r27, $r18, $r3        # r27 = global_row * K (row offset in A)
    add     $r28, $r27, $r26       # r28 = row_offset + tile_start_col
    add     $r29, $r28, $r17       # r29 = row_offset + tile_start_col + thread_col
    shl     $r29, $r29, 2          # r29 = r29 * 4 (byte offset in A)
    
    # Check if within bounds
    add     $r30, $r26, $r17       # r30 = tile_start_col + thread_col
    cmp     $r31, $r30, $r3        # r31 = (load_col < K) ? 1 : 0
    beq     $r31, $r0, skip_load_a # If out of bounds, skip load
    
    # Load from A to shared memory
    ld.w    $r31, $r5, $r29        # r31 = A[global_row][tile_start_col + thread_col]
    
    # Calculate position in tile_a
    mul     $r29, $r16, $r10       # r29 = thread_row * TILE_SIZE
    add     $r29, $r29, $r17       # r29 = thread_row * TILE_SIZE + thread_col
    shl     $r29, $r29, 2          # r29 = r29 * 4 (byte offset in tile_a)
    
    # Store to shared memory
    st.w    $r31, $r8, $r29        # tile_a[thread_row][thread_col] = A value
    
skip_load_a:
    # Thread's load position in B
    mul     $r27, $r26, $r4        # r27 = tile_start_row * N (row offset in B)
    add     $r27, $r27, $r16       # r27 = row_offset + thread_row
    mul     $r28, $r27, $r4        # r28 = (tile_start_row + thread_row) * N
    add     $r29, $r28, $r19       # r29 = row_offset + global_col
    shl     $r29, $r29, 2          # r29 = r29 * 4 (byte offset in B)
    
    # Check if within bounds
    add     $r30, $r26, $r16       # r30 = tile_start_row + thread_row
    cmp     $r31, $r30, $r3        # r31 = (load_row < K) ? 1 : 0
    beq     $r31, $r0, skip_load_b # If out of bounds, skip load
    
    # Load from B to shared memory
    ld.w    $r31, $r6, $r29        # r31 = B[tile_start_row + thread_row][global_col]
    
    # Calculate position in tile_b
    mul     $r29, $r16, $r10       # r29 = thread_row * TILE_SIZE
    add     $r29, $r29, $r17       # r29 = thread_row * TILE_SIZE + thread_col
    shl     $r29, $r29, 2          # r29 = r29 * 4 (byte offset in tile_b)
    
    # Store to shared memory
    st.w    $r31, $r9, $r29        # tile_b[thread_row][thread_col] = B value
    
skip_load_b:
    # Wait for all threads to finish loading tiles
    barrier 0
    
    # Compute partial dot product using the current tiles
    addiu   $r29, $r0, 0           # r29 = 0 (loop counter for dot product)
    
dot_product_loop:
    # Check if all elements in the tile have been processed
    cmp     $r30, $r29, $r10       # r30 = (dp_counter < TILE_SIZE) ? 1 : 0
    beq     $r30, $r0, dot_product_done
    
    # Check if we're still within K bounds
    add     $r30, $r26, $r29       # r30 = tile_start + dp_counter
    cmp     $r31, $r30, $r3        # r31 = (pos < K) ? 1 : 0
    beq     $r31, $r0, dot_product_done
    
    # Calculate offsets in shared memory tiles
    mul     $r30, $r16, $r10       # r30 = thread_row * TILE_SIZE
    add     $r30, $r30, $r29       # r30 = thread_row * TILE_SIZE + dp_counter
    shl     $r30, $r30, 2          # r30 = r30 * 4 (byte offset in tile_a)
    
    mul     $r31, $r29, $r10       # r31 = dp_counter * TILE_SIZE
    add     $r31, $r31, $r17       # r31 = dp_counter * TILE_SIZE + thread_col
    shl     $r31, $r31, 2          # r31 = r31 * 4 (byte offset in tile_b)
    
    # Load values from shared memory
    ld.w    $r30, $r8, $r30        # r30 = tile_a[thread_row][dp_counter]
    ld.w    $r31, $r9, $r31        # r31 = tile_b[dp_counter][thread_col]
    
    # Multiply and accumulate
    mul     $r30, $r30, $r31       # r30 = A value * B value
    add     $r22, $r22, $r30       # Accumulate into result
    
    # Increment counter
    addiu   $r29, $r29, 1
    
    # Loop back
    j       dot_product_loop
    
dot_product_done:
    # Wait for all threads to finish using tiles before loading next tile
    barrier 0
    
    # Increment tile counter
    addiu   $r24, $r24, 1
    
    # Loop back for next tile
    j       tile_loop
    
loop_done:
    # All tiles processed, write result to matrix C
    mul     $r26, $r18, $r4        # r26 = global_row * N
    add     $r26, $r26, $r19       # r26 = global_row * N + global_col
    shl     $r26, $r26, 2          # r26 = r26 * 4 (byte offset in C)
    
    # Store final result
    st.w    $r22, $r7, $r26        # C[global_row][global_col] = dot product result
    
exit_thread:
    # Synchronize all threads in block
    barrier 0
    
    # Exit program
    exit

# Kernel initialization function - would be called by host to setup matrices
# This is for demonstration purposes - in a real implementation, the host would
# initialize the matrices using DMA or memory mapping
.global init_matrices
init_matrices:
    # Initialize matrices with test data
    # r1 = pointer to matrix A
    # r2 = pointer to matrix B
    # r3 = dimensions (M, K, N)
    # r4 = size of each dimension (assumed square matrices for simplicity)
    
    addiu   $r5, $r0, 0            # r5 = row counter
    
init_row_loop:
    # Check if we've processed all rows
    cmp     $r6, $r5, $r4          # r6 = (row < size) ? 1 : 0
    beq     $r6, $r0, init_done
    
    # Initialize column counter
    addiu   $r7, $r0, 0            # r7 = column counter
    
init_col_loop:
    # Check if we've processed all columns
    cmp     $r8, $r7, $r4          # r8 = (col < size) ? 1 : 0
    beq     $r8, $r0, init_row_next
    
    # Calculate position in matrices
    mul     $r9, $r5, $r4          # r9 = row * size
    add     $r9, $r9, $r7          # r9 = row * size + col
    shl     $r9, $r9, 2            # r9 = (row * size + col) * 4 (byte offset)
    
    # Initialize A[row][col] = row + col (simple pattern)
    add     $r10, $r5, $r7         # r10 = row + col
    st.w    $r10, $r1, $r9         # A[row][col] = row + col
    
    # Initialize B[row][col] = row * col (different pattern)
    mul     $r10, $r5, $r7         # r10 = row * col
    st.w    $r10, $r2, $r9         # B[row][col] = row * col
    
    # Increment column counter
    addiu   $r7, $r7, 1
    
    # Loop back for next column
    j       init_col_loop
    
init_row_next:
    # Increment row counter
    addiu   $r5, $r5, 1
    
    # Loop back for next row
    j       init_row_loop
    
init_done:
    # Return to caller
    jr      $ra