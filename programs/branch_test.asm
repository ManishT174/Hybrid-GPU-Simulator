# branch_test.asm
# Test program for branch operations in GPU simulator
#
# This program tests various branch instructions and control flow:
# 1. Conditional branches (EQ, NE, LT, LE, GT, GE)
# 2. Thread divergence and reconvergence
# 3. Branch to computed addresses

.data
    .align 4
result_array:
    .space 256     # Reserve space for up to 64 results (4 bytes each)
    
# Jump table
jump_table:
    .word case0
    .word case1
    .word case2
    .word case3

.text
.global main

main:
    # Initialize base address for result array
    addiu   $r1, $r0, result_array
    
    # Initialize test data registers
    addiu   $r2, $r0, 100      # r2 = 100
    addiu   $r3, $r0, 50       # r3 = 50
    addiu   $r4, $r0, 100      # r4 = 100 (equal to r2)
    addiu   $r5, $r0, 0        # r5 = 0 (result index)
    
    # Test 1: Branch Equal (Taken)
    beq     $r2, $r4, beq_taken
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       beq_end
beq_taken:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
beq_end:
    st.w    $r10, $r1, 0       # Store result at result_array[0]
    
    # Test 2: Branch Equal (Not Taken)
    beq     $r2, $r3, beq_not_taken
    # Should execute the next instruction
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
    j       beq_not_taken_end
beq_not_taken:
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
beq_not_taken_end:
    st.w    $r10, $r1, 4       # Store result at result_array[1]
    
    # Test 3: Branch Not Equal (Taken)
    bne     $r2, $r3, bne_taken
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       bne_end
bne_taken:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
bne_end:
    st.w    $r10, $r1, 8       # Store result at result_array[2]
    
    # Test 4: Branch Not Equal (Not Taken)
    bne     $r2, $r4, bne_not_taken
    # Should execute the next instruction
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
    j       bne_not_taken_end
bne_not_taken:
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
bne_not_taken_end:
    st.w    $r10, $r1, 12      # Store result at result_array[3]
    
    # Test 5: Branch Less Than (Taken)
    blt     $r3, $r2, blt_taken
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       blt_end
blt_taken:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
blt_end:
    st.w    $r10, $r1, 16      # Store result at result_array[4]
    
    # Test 6: Branch Less Than (Not Taken)
    blt     $r2, $r3, blt_not_taken
    # Should execute the next instruction
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
    j       blt_not_taken_end
blt_not_taken:
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
blt_not_taken_end:
    st.w    $r10, $r1, 20      # Store result at result_array[5]
    
    # Test 7: Branch Less Than or Equal (Taken - Less)
    ble     $r3, $r2, ble_taken_less
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       ble_taken_less_end
ble_taken_less:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
ble_taken_less_end:
    st.w    $r10, $r1, 24      # Store result at result_array[6]
    
    # Test 8: Branch Less Than or Equal (Taken - Equal)
    ble     $r2, $r4, ble_taken_equal
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       ble_taken_equal_end
ble_taken_equal:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
ble_taken_equal_end:
    st.w    $r10, $r1, 28      # Store result at result_array[7]
    
    # Test 9: Branch Less Than or Equal (Not Taken)
    ble     $r2, $r3, ble_not_taken
    # Should execute the next instruction
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
    j       ble_not_taken_end
ble_not_taken:
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
ble_not_taken_end:
    st.w    $r10, $r1, 32      # Store result at result_array[8]
    
    # Test 10: Branch Greater Than (Taken)
    bgt     $r2, $r3, bgt_taken
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       bgt_end
bgt_taken:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
bgt_end:
    st.w    $r10, $r1, 36      # Store result at result_array[9]
    
    # Test 11: Branch Greater Than (Not Taken)
    bgt     $r3, $r2, bgt_not_taken
    # Should execute the next instruction
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
    j       bgt_not_taken_end
bgt_not_taken:
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
bgt_not_taken_end:
    st.w    $r10, $r1, 40      # Store result at result_array[10]
    
    # Test 12: Branch Greater Than or Equal (Taken - Greater)
    bge     $r2, $r3, bge_taken_greater
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       bge_taken_greater_end
bge_taken_greater:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
bge_taken_greater_end:
    st.w    $r10, $r1, 44      # Store result at result_array[11]
    
    # Test 13: Branch Greater Than or Equal (Taken - Equal)
    bge     $r2, $r4, bge_taken_equal
    # Should skip the next instruction
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
    j       bge_taken_equal_end
bge_taken_equal:
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
bge_taken_equal_end:
    st.w    $r10, $r1, 48      # Store result at result_array[12]
    
    # Test 14: Branch Greater Than or Equal (Not Taken)
    bge     $r3, $r2, bge_not_taken
    # Should execute the next instruction
    addiu   $r10, $r0, 1       # r10 = 1 (correct result)
    j       bge_not_taken_end
bge_not_taken:
    addiu   $r10, $r0, 0       # r10 = 0 (wrong result)
bge_not_taken_end:
    st.w    $r10, $r1, 52      # Store result at result_array[13]
    
    # Test 15: Thread divergence test
    # In this test, we use the thread ID to cause divergence
    # Odd-numbered threads take one path, even-numbered threads take another
    
    # Get thread ID (assume it's in special register $tid)
    tid     $r15                # r15 = thread ID
    
    # Mask with 0x1 to check if odd or even
    andi    $r16, $r15, 0x1    # r16 = r15 & 0x1 (1 if odd, 0 if even)
    
    # Branch based on odd/even
    bne     $r16, $r0, diverge_odd_path
    
    # Even thread path
    addiu   $r10, $r0, 100     # r10 = 100 (even thread result)
    j       diverge_end
    
diverge_odd_path:
    # Odd thread path
    addiu   $r10, $r0, 200     # r10 = 200 (odd thread result)
    
diverge_end:
    # All threads converge here
    addiu   $r17, $r15, 14     # r17 = thread ID + 14
    shl     $r17, $r17, 2      # r17 = r17 * 4 (offset in result array)
    st.w    $r10, $r1, $r17    # Store result based on thread ID
    
    # Test 16: Jump table
    # Use a value to index into a jump table
    addiu   $r20, $r0, 2       # r20 = 2 (jump to case 2)
    
    # Bounds check
    addiu   $r21, $r0, 4       # r21 = 4 (table size)
    cmp     $r22, $r20, $r21   # r22 = (r20 < r21) ? 1 : 0
    beq     $r22, $r0, jump_table_default  # If r20 >= r21, go to default
    
    # Calculate jump address
    addiu   $r23, $r0, jump_table    # r23 = base address of jump table
    shl     $r24, $r20, 2            # r24 = r20 * 4 (offset in jump table)
    add     $r25, $r23, $r24         # r25 = r23 + r24 (address of jump table entry)
    
    # Load target address and jump
    ld.w    $r26, $r25, 0            # r26 = jump_table[r20]
    jr      $r26                      # Jump to address in r26
    
    # Jump table cases
case0:
    addiu   $r10, $r0, 1000          # r10 = 1000 (case 0)
    j       jump_table_end
    
case1:
    addiu   $r10, $r0, 1001          # r10 = 1001 (case 1)
    j       jump_table_end
    
case2:
    addiu   $r10, $r0, 1002          # r10 = 1002 (case 2)
    j       jump_table_end
    
case3:
    addiu   $r10, $r0, 1003          # r10 = 1003 (case 3)
    j       jump_table_end
    
jump_table_default:
    addiu   $r10, $r0, 1999          # r10 = 1999 (default)
    
jump_table_end:
    st.w    $r10, $r1, 120           # Store result at result_array[30]
    
    # End of test
    exit                             # Exit program