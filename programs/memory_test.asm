# memory_test.asm
# Test program for memory operations in GPU simulator
#
# This program tests various memory operations:
# 1. Global memory access (load/store)
# 2. Shared memory access
# 3. Memory patterns (sequential, strided, random)
# 4. Different data sizes (byte, half-word, word)

.data
    .align 4
# Global memory test arrays
input_array:
    .word 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
output_array:
    .space 64      # 16 words (4 bytes each)
    
.shared
    .align 4
# Shared memory arrays
shared_array:
    .space 64      # 16 words (4 bytes each)

.text
.global main

main:
    # Initialize registers
    addiu   $r1, $r0, input_array    # r1 = base address of input array
    addiu   $r2, $r0, output_array   # r2 = base address of output array
    addiu   $r3, $r0, shared_array   # r3 = base address of shared array (in shared memory)
    addiu   $r4, $r0, 0              # r4 = loop counter
    addiu   $r5, $r0, 16             # r5 = loop limit (16 elements)
    
    # Test 1: Word access to global memory
    test_global_word:
        # Check if we've processed all elements
        cmp     $r10, $r4, $r5       # r10 = (r4 < r5) ? 1 : 0
        beq     $r10, $r0, test_global_word_end
        
        # Calculate offset
        shl     $r11, $r4, 2         # r11 = r4 * 4 (word offset)
        
        # Load from input array
        ld.w    $r12, $r1, $r11      # r12 = input_array[r4]
        
        # Modify data (multiply by 2)
        add     $r12, $r12, $r12     # r12 = r12 * 2
        
        # Store to output array
        st.w    $r12, $r2, $r11      # output_array[r4] = r12
        
        # Increment counter
        addiu   $r4, $r4, 1
        
        # Loop back
        j       test_global_word
    test_global_word_end:
    
    # Reset counter
    addiu   $r4, $r0, 0
    
    # Test 2: Byte access to global memory
    test_global_byte:
        # Check if we've processed all elements
        cmp     $r10, $r4, $r5       # r10 = (r4 < r5) ? 1 : 0
        beq     $r10, $r0, test_global_byte_end
        
        # Calculate word offset for source
        shl     $r11, $r4, 2         # r11 = r4 * 4 (word offset)
        
        # Load word from input array
        ld.w    $r12, $r1, $r11      # r12 = input_array[r4]
        
        # Calculate byte offset for destination (4 bytes per element)
        addiu   $r13, $r4, 16        # Use second half of output array
        shl     $r13, $r13, 2        # r13 = (r4 + 16) * 4
        
        # Store lowest byte to output array
        st.b    $r12, $r2, $r13      # output_array[r4 + 16] = (byte)r12
        
        # Increment counter
        addiu   $r4, $r4, 1
        
        # Loop back
        j       test_global_byte
    test_global_byte_end:
    
    # Reset counter
    addiu   $r4, $r0, 0
    
    # Test 3: Half-word access to global memory
    test_global_half:
        # Check if we've processed all elements
        cmp     $r10, $r4, $r5       # r10 = (r4 < r5) ? 1 : 0
        beq     $r10, $r0, test_global_half_end
        
        # Calculate word offset for source
        shl     $r11, $r4, 2         # r11 = r4 * 4 (word offset)
        
        # Load word from input array
        ld.w    $r12, $r1, $r11      # r12 = input_array[r4]
        
        # Calculate half-word offset for destination (2 bytes per half-word)
        addiu   $r13, $r4, 32        # Use third quarter of output array
        shl     $r13, $r13, 1        # r13 = (r4 + 32) * 2
        
        # Store lowest half-word to output array
        st.h    $r12, $r2, $r13      # output_array[r4 + 32] = (half-word)r12
        
        # Increment counter
        addiu   $r4, $r4, 1
        
        # Loop back
        j       test_global_half
    test_global_half_end:
    
    # Reset counter
    addiu   $r4, $r0, 0
    
    # Test 4: Shared memory access (word)
    test_shared_word:
        # Check if we've processed all elements
        cmp     $r10, $r4, $r5       # r10 = (r4 < r5) ? 1 : 0
        beq     $r10, $r0, test_shared_word_end
        
        # Calculate offset
        shl     $r11, $r4, 2         # r11 = r4 * 4 (word offset)
        
        # Load from input array
        ld.w    $r12, $r1, $r11      # r12 = input_array[r4]
        
        # Store to shared memory array
        st.w    $r12, $r3, $r11      # shared_array[r4] = r12
        
        # Barrier to ensure all threads have written to shared memory
        barrier 0
        
        # Load from shared memory (with offset to access data written by other threads)
        addiu   $r14, $r4, 4          # r14 = r4 + 4 (read with offset)
        and     $r14, $r14, 15        # r14 = r14 % 16 (wrap around)
        shl     $r14, $r14, 2         # r14 = r14 * 4 (word offset)
        ld.w    $r15, $r3, $r14       # r15 = shared_array[(r4 + 4) % 16]
        
        # Store back to output array
        st.w    $r15, $r2, $r11       # output_array[r4] = r15
        
        # Increment counter
        addiu   $r4, $r4, 1
        
        # Loop back
        j       test_shared_word
    test_shared_word_end:
    
    # Reset counter
    addiu   $r4, $r0, 0
    
    # Test 5: Strided access to global memory
    test_strided_access:
        # Check if we've processed all elements (only 8 in this test)
        addiu   $r16, $r0, 8         # r16 = 8 (half the elements)
        cmp     $r10, $r4, $r16      # r10 = (r4 < r16) ? 1 : 0
        beq     $r10, $r0, test_strided_access_end
        
        # Calculate strided offset (stride of 2 words)
        shl     $r11, $r4, 3         # r11 = r4 * 8 (stride of 2 words = 8 bytes)
        
        # Load from input array with stride
        ld.w    $r12, $r1, $r11      # r12 = input_array[r4*2]
        
        # Store to output array (contiguously)
        shl     $r13, $r4, 2         # r13 = r4 * 4 (word offset)
        addiu   $r14, $r13, 128      # Use last quarter of output array
        st.w    $r12, $r2, $r14      # output_array[r4 + 32] = r12
        
        # Increment counter
        addiu   $r4, $r4, 1
        
        # Loop back
        j       test_strided_access
    test_strided_access_end:
    
    # End of test
    exit                       # Exit program