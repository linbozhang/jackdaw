#!/bin/bash
cd /Users/zhanglinbo/workspace/jackdaw
unset RUST_BACKTRACE
exec env DYLD_LIBRARY_PATH="/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib" JACKDAW_REMOTE_PORT=15930 JACKDAW_WINDOW_SIZE=1600x900 JACKDAW_OPEN_PROJECT="/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim" ./target/debug/jackdaw
