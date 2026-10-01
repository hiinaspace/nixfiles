#!/usr/bin/env python3
"""Run on Steam Frame to query/set SteamVR's default native-app refresh rate.

Uses Valve's IVRSettings_003 function table from openvr_capi.h. WiVRn should
keep preferred_refresh_rate=0 so its server follows the local runtime rate.
Reconnect WiVRn after changing this setting. Original value on sneed: 72 Hz.
"""
import argparse
import ctypes as c


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set", type=float, choices=(72, 90), dest="rate")
    parser.add_argument("--library", default="/opt/steamvr/bin/linuxarm64/libopenvr_api.so")
    parser.add_argument("--key", default="defaultPerAppRefreshRate",
                        choices=("defaultPerAppRefreshRate", "preferredRefreshRate"))
    args = parser.parse_args()
    library = c.CDLL(args.library)
    error = c.c_int()
    library.VR_InitInternal2.argtypes = [c.POINTER(c.c_int), c.c_int, c.c_char_p]
    library.VR_InitInternal2.restype = c.c_uint32
    library.VR_InitInternal2(c.byref(error), 3, None)  # VRApplication_Background
    if error.value:
        raise RuntimeError(f"OpenVR init error {error.value}")
    try:
        library.VR_GetGenericInterface.argtypes = [c.c_char_p, c.POINTER(c.c_int)]
        library.VR_GetGenericInterface.restype = c.c_void_p
        pointer = library.VR_GetGenericInterface(b"FnTable:IVRSettings_003", c.byref(error))
        if not pointer or error.value:
            raise RuntimeError(f"IVRSettings error {error.value}")
        table = c.cast(pointer, c.POINTER(c.c_void_p))
        get_float = c.CFUNCTYPE(c.c_float, c.c_char_p, c.c_char_p, c.POINTER(c.c_int))(table[7])
        set_float = c.CFUNCTYPE(None, c.c_char_p, c.c_char_p, c.c_float, c.POINTER(c.c_int))(table[3])
        section, key = b"steamvr", args.key.encode()
        previous = get_float(section, key, c.byref(error))
        if error.value:
            raise RuntimeError(f"Read error {error.value}")
        print(f"{args.key}: {previous:g} Hz")
        if args.rate is not None:
            set_float(section, key, args.rate, c.byref(error))
            if error.value:
                raise RuntimeError(f"Write error {error.value}")
            actual = get_float(section, key, c.byref(error))
            if error.value or actual != args.rate:
                raise RuntimeError(f"Readback failed: {actual}, error {error.value}")
            print(f"Updated {args.key}: {actual:g} Hz")
    finally:
        library.VR_ShutdownInternal()


if __name__ == "__main__":
    main()
