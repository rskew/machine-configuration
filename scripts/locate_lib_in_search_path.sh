#!/usr/bin/env bash
lib_name="$1"
LD_DEBUG=libs python3 -c "import ctypes; ctypes.CDLL('$lib_name')" 2>&1 \
    | grep -A 1000 "initialize program: python" \
    | grep -A 3 "find library=$lib_name"
