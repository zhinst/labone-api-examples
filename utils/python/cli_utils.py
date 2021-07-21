"""
Module that provides a comandline interface for the python examples.
It uses docopt to generate the commandline and does the following tests befor calling an example:
    - checks if the LabOne version matches the required version in the example.
    - checks if the device(s) match(s) the required one(s) in the examples.
"""
import re
import zhinst.ziPython


def extract_version(doc):
    """
    Extracts the version from the docstring of an Example.
    The Version is specified in the following format:
    LabOne Version >= <major>.<minor>[.<minor>]

    Returns:
        (major, minor, build)

    Raises:
        Exception if the Version has the wrong format.
        Exception if there is no or more than one LabOne Version specified.
    """
    results = re.findall(r"LabOne Version >= ([0-9\.]*)", doc)
    if len(results) == 0:
        raise Exception("No LabOne Version is defined in the docstring")
    if len(results) > 1:
        raise Exception(
            "more than one LabOne version is defined but only one is allowed"
        )

    version = results[0]
    major_minor_format = bool(re.match(r"^\d\d\.\d\d$", version))
    major_minor_build_format = bool(re.match(r"^\d\d\.\d\d.\d+$", version))

    if major_minor_format:
        min_major, min_minor = map(int, version.split("."))
        min_build = 0
    elif major_minor_build_format:
        min_major, min_minor, min_build = map(int, version.split("."))
    else:
        raise Exception(
            f"Wrong ziPython version format: {version}. Supported format: MAJOR.MINOR or \
                MAJOR.MINOR.BUILD"
        )

    return (min_major, min_minor, min_build)


def check_version(doc):
    """
    Check if the specified LabOne version is matched.

    Raises:
        Exception if the Version has the wrong format.
        Exception if there is no or more than one LabOne Version specified.
        Exception if the LabOne version is not matched.
    """
    (min_major, min_minor, min_build) = extract_version(doc)
    installed_version = zhinst.ziPython.__version__
    major, minor, build = map(int, installed_version.split("."))

    if (min_major, min_minor, min_build) >= (major, minor, build):
        raise Exception(
            f"Example requires ziPython version"
            f"{min_major}.{min_minor}.{min_build} or greater (installed: {installed_version})."
            f"Please visit the Zurich Instruments website to update."
        )


def extract_devices(doc):
    """
    Extracts the required devices from the docstring of an Example.

    Returns:
        device_dict  Dictionary with the required devices.
                     key: variable name
                     value: dict with potential device types.
                            key: device type
                            value: list with required options
    """
    results = re.findall(r"(<(.*?)>|--([^ \n]+)).*?\[device_type: (.*?)\]", doc)
    device_dict = {}
    for result in results:
        if result[1]:
            name = result[1]
        if result[2]:
            name = result[2]
        devices = result[3].split("|")
        device_dict_opt = {}
        for device in devices:
            regex_result = re.findall(r"([\.\*A-Z0-9]+)(\(([A-Z,0-9]*)\))?", device)
            if len(regex_result) != 1:
                raise Exception(f"Invalid device {device} in docstring")
            device_type = regex_result[0][0]
            device_opt = regex_result[0][2].split(",")
            device_dict_opt[device_type] = device_opt
        device_dict[name] = device_dict_opt
    return device_dict


def check_single_device(device_id, dev_types, device_variable):
    """
    Check if a devices match the ones required.

    Raises:
        Exception if a specified device does not match the requirements.
    """

    discovery = zhinst.ziPython.ziDiscovery()
    device_disc = discovery.find(device_id).lower()
    props = discovery.get(device_disc)
    if props["devicetype"] == "":
        raise Exception(f"device {device_id} could not been discovered")
    device_match = False
    error_text = ""
    for dev_type, dev_opt in dev_types.items():
        if re.search(dev_type, props["devicetype"]):
            option_missing = False
            for option in dev_opt:
                if option not in props["options"] and option != "":
                    option_missing = True
                    error_text = (
                        error_text
                        + f"missing option {option} for device {device_id}.\n"
                    )
                    break
            if not option_missing:
                device_match = True
                break
    if not device_match:
        if error_text:
            raise Exception(error_text)
        raise Exception(
            f"The device {device_id} does not match the requirements of {device_variable}"
        )


def check_devices(doc, args):
    """
    Check if the specified devices match the ones required.

    Raises:
        Exception if a specified device does not match the requirements.
    """

    print("checking devices")

    device_dict = extract_devices(doc)

    for device_variable, dev_types in device_dict.items():
        # search the given args for the device ids given for the variable
        device_ids = args[device_variable]
        if isinstance(device_ids, str):
            device_ids = [device_ids]
        # check every device_id
        for device_id in device_ids:
            check_single_device(device_id, dev_types, device_variable)


def run_commandline(func, doc):
    """
    create a command line interface for the give function.
    The required information are extracted form the docstring
    """
    from docopt import docopt

    raw_args = docopt(doc)
    args = {}

    from typing import get_type_hints

    hints = get_type_hints(func)

    for arg in raw_args:
        arg_new = arg.strip("-").strip("<").strip(">")
        if arg_new in hints:
            args[arg_new] = hints[arg_new](raw_args[arg])
        elif arg_new.startswith("no-"):
            print(arg_new)
            invert_arg = arg_new.lstrip("no-")
            print(hints[invert_arg])
            if invert_arg in hints and hints[invert_arg] == bool:
                print(invert_arg)
                args[invert_arg] = not bool(raw_args[arg])
        else:
            args[arg_new] = raw_args[arg]
    args.pop("help")

    print(args)

    check_version(doc)
    check_devices(doc, args)

    return_value = func(**args)
    if return_value is not None:
        print(return_value)
