.SUFFIXES: .c .o

COMPILE = $(CC) -g -O3 -Wall -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -g -DDEBUG_FLAG
INC_PATH = -I/usr/local/include
LIB_PATH = -lfastcommon -lpthread

ALL_PRGS = test_allocator test_skiplist test_multi_skiplist test_mblock test_blocked_queue \
           test_id_generator test_ini_parser test_char_convert test_char_convert_loader \
           test_logger test_skiplist_set test_crc32 test_thourands_seperator test_sched_thread \
           test_json_parser test_pthread_lock test_uniq_skiplist test_split_string \
           test_server_id_func test_pipe test_atomic test_file_write_hole test_file_lock \
           test_pthread_wait test_thread_pool test_data_visible test_mutex_lock_perf \
           test_queue_perf test_normalize_path test_sorted_array test_sorted_queue   \
           test_thread_local test_memcpy mblock_benchmark cpool_benchmark

all: $(ALL_PRGS)

.c:
	$(COMPILE) -o $@ $< $(LIB_PATH) $(INC_PATH)
.c.o:
	$(COMPILE) -c -o $@ $<  $(INC_PATH)
clean:
	rm -f $(ALL_PRGS)

