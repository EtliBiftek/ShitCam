test_file = "build/test_fs_env.tmp"
write_file(test_file, "shitcam data")
print(file_exists(test_file))
del_ok = delete_file(test_file)
print(del_ok)
print(file_exists(test_file))

env_key = "SHITCAM_TEST_VAR"
set_env(env_key, "hello_env")
val = get_env(env_key)
print(val)
