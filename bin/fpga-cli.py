#!/usr/bin/env python
# encoding: utf-8
"""
A stub with semi-functional interface suitable for test FPGA with FPGA enabled
OpenStack.
See --help for this command and README.rst for more details.
"""

import argparse
import json
import os
import sys


# change this to adjust the amount of regions
FPGA_REGIONS = 2
JSON = "/tmp/_fpga_data_stub.json"


def write_data(data=None):
    """create and wrtie initial data to the json file"""

    if not data:
        data = {"total": FPGA_REGIONS,
                "used": 0,
                'regions': [0 for _ in range(FPGA_REGIONS)]}

    with open(JSON, "w") as fobj:
        json.dump(data, fobj)


def read_data():
    """read json file and return deserialized dict"""
    with open(JSON) as fobj:
        return json.load(fobj)


class RetVal(object):
    """Simple class for result storage"""
    def __init__(self, message="", exit_code=0):
        self.message = message
        self.exit_code = exit_code


def status(args):
    """Get status"""
    if os.getenv("FPGA_ERROR"):
        return RetVal("Error!", 127)

    try:
        data = read_data()
    except (IOError, ValueError):
        return RetVal("Error!", 128)

    return RetVal("Used regions: %(used)s/%(total)s" % data)


def erase(args):
    """erase fpga"""
    if os.getenv("FPGA_ERROR"):
        return RetVal("Unable to erase FPGA", 31)

    try:
        data = read_data()
    except (IOError, ValueError):
        return RetVal("Unable to erase FPGA", 32)

    index = data['total'] - (data['total'] - data['used']) - 1
    if index < 0:
        return RetVal("Unable to erase FPGA device %s no such device" %
                      args.device, 33)

    data['regions'][index] = 0
    data['used'] = data['used'] - 1
    write_data(data)

    return RetVal()


def burn(args):
    """Burn the fpga stub! :)"""
    assert args.image_id
    if os.getenv("FPGA_ERROR"):
        return RetVal("Unable to burn FPGA", 64)

    try:
        data = read_data()
    except (IOError, ValueError):
        return RetVal("Unable to burn FPGA", 64)

    if all(data['regions']):
        return RetVal("Unable to burn FPGA - no available regions", 65)

    index = data['regions'].index(0)
    data['regions'][index] = 1
    data['used'] += 1
    write_data(data)

    return RetVal("/dev/fpga%s" % index)


def main():
    """main"""

    usage = ("Change FPGA_REGIONS in this file, to set desired amount of "
             "regions to mock.\n"
             "After that, remove `" + JSON + "' file for refreshing the\n"
             "state and amount of regions.")
    parser = argparse.ArgumentParser(description=usage)
    subparser = parser.add_subparsers()

    _status = subparser.add_parser("status", help="Mimic FPGA status. Set env"
                                   " variable FPGA_ERROR to force the error"
                                   " situation.")
    _status.set_defaults(func=status)

    _erase = subparser.add_parser("erase", help="Mimic erase of the FPGA "
                                  "device. Set env variable FPGA_ERROR to "
                                  "make it fail.")
    _erase.add_argument("device")
    _erase.set_defaults(func=erase)

    _burn = subparser.add_parser("burn", help="Mimic flashing provided image "
                                 "to the FPGA. Set env variable FPGA_ERROR to"
                                 " make it fail.")
    _burn.add_argument("image_id")
    _burn.set_defaults(func=burn)

    args = parser.parse_args()

    if not os.path.exists(JSON):
        write_data()

    retval = args.func(args)

    if retval.exit_code:
        sys.stderr.write(retval.message + "\n")
    else:
        sys.stdout.write(retval.message + "\n")

    sys.exit(retval.exit_code)


if __name__ == '__main__':
    main()
