# vector_add.asm
# Example vector addition program for GPU simulator
#
# This program demonstrates a simple GPGPU computation:
# Each thread computes C[i] = A[i] + B[i] for a different index i
# The program uses thread and warp IDs to determine which elements to process

.data
    .align 4
# Vector dimensions
vector_length:
    .word 1024                     # Length of vectors (1024 elements)

# Input vectors
vector_a:
    .space 4096                    # Vector A: 1024 elements * 4 bytes
vector_b:
    .space 4096                    # Vector B: 1024 elements * 4 bytes
    
# Output vector
vector_c:
    .space 4096                    # Vector C: 1024 elements * 4 bytes

.text
.global main

main:
    # Initialize registers
    addiu   $r1, $r0, vector_a     # r1 = base address of vector A
    addiu   $r2, $r0, vector_b     # r2 = base address of vector B
    addiu   $r3, $r0, vector_c     # r3 = base address of vector C
    addiu   $r4, $r0, vector_length
    ld.w    $r4, $r4, 0            # r4 = vector length (1024)
    
    # Get thread and warp IDs
    tid     $r5                     # r5 = thread ID within warp (0-31)
    warpid  $r6                     # r6 = warp ID
    
    # Calculate global thread ID
    shl     $r7, $r6, 5            # r7 = warp ID * 32 (threads per warp)
    add     $r8, $r7, $r5          # r8 = global thread ID (warp ID * 32 + thread ID)
    
    # Check if thread ID is within vector bounds
    cmp     $r9, $r8, $r4          # r9 = (global_thread_id < vector_length) ? 1 : 0
    beq     $r9, $r0, exit_thread  # If global_thread_id >= vector_length, exit
    
    # Calculate offset for this thread
    shl     $r10, $r8, 2           # r10 = global_thread_id * 4 (byte offset)
    
    # Load A[global_thread_id] and B[global_thread_id]
    ld.w    $r11, $r1, $r10        # r11 = A[global_thread_id]
    ld.w    $r12, $r2, $r10        # r12 = B[global_thread_id]
    
    # Compute C[global_thread_id] = A[global_thread_id] + B[global_thread_id]
    add     $r13, $r11, $r12       # r13 = r11 + r12
    
    # Store result to C[global_thread_id]
    st.w    $r13, $r3, $r10        # C[global_thread_id] = r13
    
exit_thread:
    # Synchronize all threads in block using barrier
    barrier 0
    
    # Exit program
    exit

# Kernel initialization function - would be called by host to setup vectors
# This is for demonstration purposes - in a real implementation, the host would
# initialize the vectors using DMA or memory mapping
.global init_vectors
init_vectors:
    # Initialize vectors with test data
    # r1 = pointer to vector A
    # r2 = pointer to vector B
    # r3 = length of vectors
    
    addiu   $r4, $r0, 0            # r4 = loop counter
    
init_loop:
    # Check if we've processed all elements
    cmp     $r5, $r4, $r3          # r5 = (counter < length) ? 1 : 0
    beq     $r5, $r0, init_done
    
    # Calculate offset
    shl     $r6, $r4, 2            # r6 = counter * 4 (byte offset)
    
    # Set A[i] = i
    st.w    $r4, $r1, $r6          # A[counter] = counter
    
    # Set B[i] = i * 2
    shl     $r7, $r4, 1            # r7 = counter * 2
    st.w    $r7, $r2, $r6          # B[counter] = counter * 2
    
    # Increment counter
    addiu   $r4, $r4, 1
    
    # Loop back
    j       init_loop
    
init_done:
    # Return to caller
    jr      $ra