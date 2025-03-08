# sync_test.asm
# Test program for synchronization operations in GPU simulator
#
# This program tests various synchronization mechanisms:
# 1. Barriers (for synchronizing threads within a block)
# 2. Atomic operations (for thread-safe memory access)
# 3. Thread voting functions (all, any)

.data
    .align 4
result_array:
    .space 256     # Reserve space for up to 64 results (4 bytes each)
    
atomic_counter:
    .word 0        # Shared counter for atomic operations
    
barrier_counter:
    .word 0        # Counter to verify barrier synchronization

.shared
    .align 4
shared_array:
    .space 128     # Shared memory array (32 words)

.text
.global main

main:
    # Initialize base address for arrays
    addiu   $r1, $r0, result_array     # r1 = base address of result array
    addiu   $r2, $r0, atomic_counter   # r2 = address of atomic counter
    addiu   $r3, $r0, barrier_counter  # r3 = address of barrier counter
    addiu   $r4, $r0, shared_array     # r4 = base address of shared array
    
    # Get thread ID and warp ID
    tid     $r10                        # r10 = thread ID
    warpid  $r11                        # r11 = warp ID
    
    ###############################################
    # Test 1: Basic Barrier Synchronization
    ###############################################
    
    # Phase 1: Each thread writes its ID to shared memory
    shl     $r12, $r10, 2               # r12 = thread ID * 4 (word offset)
    st.w    $r10, $r4, $r12             # shared_array[thread_id] = thread_id
    
    # All threads must arrive at barrier before continuing
    barrier 0
    
    # Phase 2: Each thread reads from a different location
    # (thread 0 reads from thread 1's location, thread 1 reads from thread 2's, etc.)
    addiu   $r13, $r10, 1               # r13 = thread ID + 1
    and     $r13, $r13, 31              # r13 = (thread ID + 1) % 32 (wrap around)
    shl     $r13, $r13, 2               # r13 = r13 * 4 (word offset)
    ld.w    $r14, $r4, $r13             # r14 = shared_array[(thread_id + 1) % 32]
    
    # Store the value read into result array (only happens correctly if barrier worked)
    st.w    $r14, $r1, $r12             # result_array[thread_id] = value_read
    
    # All threads arrive at barrier again
    barrier 0
    
    ###############################################
    # Test 2: Atomic Add
    ###############################################
    
    # Each thread atomically increments the counter
    atomic.add  $r15, $r2, 1            # Atomic add: counter += 1, returns original value
    
    # Store the original value returned by atomic.add
    addiu   $r16, $r10, 32              # r16 = thread ID + 32
    shl     $r16, $r16, 2               # r16 = r16 * 4 (word offset)
    st.w    $r15, $r1, $r16             # result_array[thread_id + 32] = original atomic value
    
    # All threads arrive at barrier
    barrier 0
    
    # Only thread 0 checks the final counter value
    bne     $r10, $r0, skip_check_atomic
    
    ld.w    $r18, $r2, 0                # r18 = final atomic counter value
    st.w    $r18, $r1, 128              # result_array[32] = final counter value
    
skip_check_atomic:
    # All threads arrive at barrier
    barrier 0
    
    ###############################################
    # Test 3: Atomic CAS (Compare And Swap)
    ###############################################
    
    # Reset counter (only thread 0)
    bne     $r10, $r0, skip_reset_cas
    
    st.w    $r0, $r2, 0                 # atomic_counter = 0
    
skip_reset_cas:
    # All threads arrive at barrier
    barrier 0
    
    # Each thread atomically tries to change the counter from 0 to its ID
    addiu   $r19, $r0, 0                # r19 = 0 (expected value)
    atomic.cas  $r20, $r2, $r19, $r10   # Atomic CAS: if counter==0, counter=thread_id
    
    # Store the original value returned by atomic.cas
    addiu   $r21, $r10, 64              # r21 = thread ID + 64
    shl     $r21, $r21, 2               # r21 = r21 * 4 (word offset)
    st.w    $r20, $r1, $r21             # result_array[thread_id + 64] = original CAS value
    
    # All threads arrive at barrier
    barrier 0
    
    # Only thread 0 checks the final counter value
    bne     $r10, $r0, skip_check_cas
    
    ld.w    $r22, $r2, 0                # r22 = final atomic counter value after CAS
    st.w    $r22, $r1, 132              # result_array[33] = final CAS value
    
skip_check_cas:
    # All threads arrive at barrier
    barrier 0
    
    ###############################################
    # Test 4: Thread Voting (All)
    ###############################################
    
    # Test "all" voting - All threads execute a comparison and vote
    # We'll check if all thread IDs are less than 100 (should be true)
    addiu   $r25, $r0, 100              # r25 = 100
    cmp     $r26, $r10, $r25            # r26 = (thread_id < 100) ? 1 : 0
    
    # Execute vote.all instruction - returns 1 if all threads have non-zero predicate
    vote.all $r27, $r26                 # r27 = 1 if all threads voted true, 0 otherwise
    
    # Only thread 0 stores the result
    bne     $r10, $r0, skip_store_vote_all
    
    st.w    $r27, $r1, 136              # result_array[34] = vote.all result
    
skip_store_vote_all:
    # All threads arrive at barrier
    barrier 0
    
    ###############################################
    # Test 5: Thread Voting (Any)
    ###############################################
    
    # Test "any" voting - Check if any thread ID equals 7 (should be true)
    addiu   $r28, $r0, 7                # r28 = 7
    beq     $r10, $r28, set_vote_true   # If thread_id == 7, set vote to true
    addiu   $r29, $r0, 0                # r29 = 0 (false for most threads)
    j       do_vote_any
    
set_vote_true:
    addiu   $r29, $r0, 1                # r29 = 1 (true for thread 7)
    
do_vote_any:
    # Execute vote.any instruction - returns 1 if any thread has non-zero predicate
    vote.any $r30, $r29                 # r30 = 1 if any thread voted true, 0 otherwise
    
    # Only thread 0 stores the result
    bne     $r10, $r0, skip_store_vote_any
    
    st.w    $r30, $r1, 140              # result_array[35] = vote.any result
    
skip_store_vote_any:
    # All threads arrive at barrier
    barrier 0
    
    ###############################################
    # Test 6: Atomic Exchange
    ###############################################
    
    # Reset counter (only thread 0)
    bne     $r10, $r0, skip_reset_exchange
    
    st.w    $r0, $r2, 0                 # atomic_counter = 0
    
skip_reset_exchange:
    # All threads arrive at barrier
    barrier 0
    
    # Each thread atomically exchanges the counter with its ID
    atomic.exch  $r31, $r2, $r10        # Atomic exchange: counter = thread_id, return old value
    
    # Store the original value returned by atomic.exch
    addiu   $r24, $r10, 96              # r24 = thread ID + 96
    shl     $r24, $r24, 2               # r24 = r24 * 4 (word offset)
    st.w    $r31, $r1, $r24             # result_array[thread_id + 96] = original exchange value
    
    # All threads arrive at barrier
    barrier 0
    
    # Only thread 0 checks the final counter value
    bne     $r10, $r0, skip_check_exchange
    
    ld.w    $r23, $r2, 0                # r23 = final atomic counter value after exchange
    st.w    $r23, $r1, 144              # result_array[36] = final exchange value
    
skip_check_exchange:
    # All threads arrive at barrier
    barrier 0
    
    ###############################################
    # Test 7: Arrive and Wait Barrier Test
    ###############################################
    
    # Phase 1: Each thread increments barrier_counter, then arrives at barrier
    atomic.add  $r15, $r3, 1            # Atomically increment barrier_counter
    
    # Arrive at barrier but don't wait yet
    arrive 1
    
    # Add a second increment to barrier_counter
    atomic.add  $r15, $r3, 1            # Atomically increment barrier_counter again
    
    # Wait at barrier (all threads must have arrived before proceeding)
    wait 1
    
    # Only thread 0 checks the final barrier_counter value
    bne     $r10, $r0, skip_check_barrier
    
    ld.w    $r17, $r3, 0                # r17 = final barrier counter value
    st.w    $r17, $r1, 148              # result_array[37] = final barrier counter
    
skip_check_barrier:
    # All threads arrive at final barrier
    barrier 0
    
    # End of test
    exit                               # Exit program