# alu_test.asm
# Test program for ALU operations in GPU simulator
#
# This program tests all ALU operations with different register and immediate operands
# Each test stores the result in a result array for verification

.data
    .align 4
result_array:
    .space 256     # Reserve space for up to 64 results (4 bytes each)
    
.text
.global main

main:
    # Initialize base address for result array
    addiu   $r1, $r0, result_array
    
    # Initialize test data registers
    addiu   $r2, $r0, 100      # r2 = 100
    addiu   $r3, $r0, 50       # r3 = 50
    addiu   $r4, $r0, 0x0F0F   # r4 = 0x0F0F
    addiu   $r5, $r0, 0xF0F0   # r5 = 0xF0F0
    addiu   $r6, $r0, -10      # r6 = -10
    
    # 1. Test ADD (Register)
    add     $r10, $r2, $r3     # r10 = r2 + r3 = 100 + 50 = 150
    st.w    $r10, $r1, 0       # Store result at result_array[0]
    
    # 2. Test ADD (Immediate)
    addi    $r10, $r2, 25      # r10 = r2 + 25 = 100 + 25 = 125
    st.w    $r10, $r1, 4       # Store result at result_array[1]
    
    # 3. Test SUB (Register)
    sub     $r10, $r2, $r3     # r10 = r2 - r3 = 100 - 50 = 50
    st.w    $r10, $r1, 8       # Store result at result_array[2]
    
    # 4. Test SUB (Immediate)
    subi    $r10, $r2, 25      # r10 = r2 - 25 = 100 - 25 = 75
    st.w    $r10, $r1, 12      # Store result at result_array[3]
    
    # 5. Test MUL (Register)
    mul     $r10, $r2, $r3     # r10 = r2 * r3 = 100 * 50 = 5000
    st.w    $r10, $r1, 16      # Store result at result_array[4]
    
    # 6. Test MUL (Immediate)
    muli    $r10, $r2, 5       # r10 = r2 * 5 = 100 * 5 = 500
    st.w    $r10, $r1, 20      # Store result at result_array[5]
    
    # 7. Test DIV (Register)
    div     $r10, $r2, $r3     # r10 = r2 / r3 = 100 / 50 = 2
    st.w    $r10, $r1, 24      # Store result at result_array[6]
    
    # 8. Test DIV (Immediate)
    divi    $r10, $r2, 4       # r10 = r2 / 4 = 100 / 4 = 25
    st.w    $r10, $r1, 28      # Store result at result_array[7]
    
    # 9. Test AND (Register)
    and     $r10, $r4, $r5     # r10 = r4 & r5 = 0x0F0F & 0xF0F0 = 0x0000
    st.w    $r10, $r1, 32      # Store result at result_array[8]
    
    # 10. Test AND (Immediate)
    andi    $r10, $r4, 0xFF    # r10 = r4 & 0xFF = 0x0F0F & 0xFF = 0x0F
    st.w    $r10, $r1, 36      # Store result at result_array[9]
    
    # 11. Test OR (Register)
    or      $r10, $r4, $r5     # r10 = r4 | r5 = 0x0F0F | 0xF0F0 = 0xFFFF
    st.w    $r10, $r1, 40      # Store result at result_array[10]
    
    # 12. Test OR (Immediate)
    ori     $r10, $r4, 0xF000  # r10 = r4 | 0xF000 = 0x0F0F | 0xF000 = 0xFF0F
    st.w    $r10, $r1, 44      # Store result at result_array[11]
    
    # 13. Test XOR (Register)
    xor     $r10, $r4, $r5     # r10 = r4 ^ r5 = 0x0F0F ^ 0xF0F0 = 0xFFFF
    st.w    $r10, $r1, 48      # Store result at result_array[12]
    
    # 14. Test XOR (Immediate)
    xori    $r10, $r4, 0xFF    # r10 = r4 ^ 0xFF = 0x0F0F ^ 0xFF = 0x0FF0
    st.w    $r10, $r1, 52      # Store result at result_array[13]
    
    # 15. Test SHL (Register)
    shl     $r10, $r2, $r3     # r10 = r2 << (r3 % 32) = 100 << (50 % 32) = 100 << 18 = 26214400
    st.w    $r10, $r1, 56      # Store result at result_array[14]
    
    # 16. Test SHL (Immediate)
    shli    $r10, $r2, 4       # r10 = r2 << 4 = 100 << 4 = 1600
    st.w    $r10, $r1, 60      # Store result at result_array[15]
    
    # 17. Test SHR (Register)
    shr     $r10, $r2, $r3     # r10 = r2 >> (r3 % 32) = 100 >> (50 % 32) = 100 >> 18 = 0
    st.w    $r10, $r1, 64      # Store result at result_array[16]
    
    # 18. Test SHR (Immediate)
    shri    $r10, $r2, 2       # r10 = r2 >> 2 = 100 >> 2 = 25
    st.w    $r10, $r1, 68      # Store result at result_array[17]
    
    # 19. Test CMP (Register) - Less than
    cmp     $r10, $r3, $r2     # r10 = (r3 < r2) ? 1 : 0 = (50 < 100) ? 1 : 0 = 1
    st.w    $r10, $r1, 72      # Store result at result_array[18]
    
    # 20. Test CMP (Register) - Greater than
    cmp     $r10, $r2, $r3     # r10 = (r2 < r3) ? 1 : 0 = (100 < 50) ? 1 : 0 = 0
    st.w    $r10, $r1, 76      # Store result at result_array[19]
    
    # 21. Test CMP (Immediate)
    cmpi    $r10, $r2, 150     # r10 = (r2 < 150) ? 1 : 0 = (100 < 150) ? 1 : 0 = 1
    st.w    $r10, $r1, 80      # Store result at result_array[20]
    
    # 22. Test MIN (Register)
    min     $r10, $r2, $r3     # r10 = min(r2, r3) = min(100, 50) = 50
    st.w    $r10, $r1, 84      # Store result at result_array[21]
    
    # 23. Test MIN (Immediate)
    mini    $r10, $r2, 75      # r10 = min(r2, 75) = min(100, 75) = 75
    st.w    $r10, $r1, 88      # Store result at result_array[22]
    
    # 24. Test MAX (Register)
    max     $r10, $r2, $r3     # r10 = max(r2, r3) = max(100, 50) = 100
    st.w    $r10, $r1, 92      # Store result at result_array[23]
    
    # 25. Test MAX (Immediate)
    maxi    $r10, $r2, 150     # r10 = max(r2, 150) = max(100, 150) = 150
    st.w    $r10, $r1, 96      # Store result at result_array[24]
    
    # 26. Test ABS
    abs     $r10, $r6          # r10 = abs(r6) = abs(-10) = 10
    st.w    $r10, $r1, 100     # Store result at result_array[25]
    
    # 27. Test NEG
    neg     $r10, $r2          # r10 = -r2 = -100
    st.w    $r10, $r1, 104     # Store result at result_array[26]
    
    # End of test
    exit                       # Exit program