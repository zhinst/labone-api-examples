# Copyright 2017 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to perform a manually triggered autoranging for impedance while working in
manual range mode. Sets the device to impedance manual range mode and execute
a single auto ranging event.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with IA option
    * Connect Impedance Testfixture and attach a 1kOhm resistor

Usage:
    example_autoranging_impedance.py <device_id>
    example_autoranging_impedance.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: MF*(IA)]

Options:
    -h --help                 Show this screen.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""
import time
import zhinst.utils


def run_example(device_id: str):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    err_msg = "This example only supports instruments with IA option."
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id, apilevel_example, required_options=["IA"], required_err_msg=err_msg
    )
    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration: disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all devices with IA option. The values below may be
    # changed if the instrument has multiple IA modules.
    imp_index = 0
    curr_index = daq.getInt("/%s/imps/%d/current/inputselect" % (device, imp_index))
    volt_index = daq.getInt("/%s/imps/%d/voltage/inputselect" % (device, imp_index))
    man_curr_range = 10e-3
    man_volt_range = 10e-3
    exp_settings = [
        ["/%s/imps/%d/enable" % (device, imp_index), 1],
        ["/%s/imps/%d/mode" % (device, imp_index), 0],
        ["/%s/imps/%d/auto/output" % (device, imp_index), 1],
        ["/%s/imps/%d/auto/bw" % (device, imp_index), 1],
        ["/%s/imps/%d/freq" % (device, imp_index), 500],
        ["/%s/imps/%d/auto/inputrange" % (device, imp_index), 0],
        ["/%s/currins/%d/range" % (device, curr_index), man_curr_range],
        ["/%s/sigins/%d/range" % (device, volt_index), man_volt_range],
    ]
    daq.set(exp_settings)
    # Perform a global synchronisation between the device and the data server:
    # Ensure that the settings have taken effect on the device before setting
    # the next configuration.
    daq.sync()

    # After setting the device in manual ranging mode we want to trigger manually
    # a one time auto ranging to find a suitable range. Therefore, we trigger the
    # auto ranging for the current input as well as for the voltage input.
    trigger_auto_ranging = [
        ["/%s/currins/%d/autorange" % (device, curr_index), 1],
        ["/%s/sigins/%d/autorange" % (device, volt_index), 1],
    ]
    print("Start auto ranging. This takes a few seconds.")
    daq.set(trigger_auto_ranging)

    t_start = time.time()
    timeout = 20
    finished = 0
    # The auto ranging takes some time. We do not want to continue before the
    # best range is found. Therefore, we implement a loop to check if the auto
    # ranging is finished. These nodes maintain value 1 until autoranging has
    # finished.
    while not finished:
        time.sleep(0.5)
        currins_autorange = daq.getInt(
            "/%s/currins/%d/autorange" % (device, curr_index)
        )
        sigins_autorange = daq.getInt("/%s/sigins/%d/autorange" % (device, volt_index))
        # We are finished when both nodes have been set back to 0 by the device.
        finished = (currins_autorange == 0) and (sigins_autorange == 0)
        if time.time() - t_start > timeout:
            raise Exception(f"Autoranging failed after {timeout} seconds.")
    print(f"Auto ranging finished after {time.time() - t_start:0.1f} s.")

    auto_curr_range = daq.getDouble("/%s/currins/%d/range" % (device, curr_index))
    auto_volt_range = daq.getDouble("/%s/sigins/%d/range" % (device, volt_index))
    print(
        f"Current range changed from {man_curr_range:0.1e} A to {auto_curr_range:0.1e} A."
    )
    print(
        f"Voltage range changed from {man_volt_range:0.1e} V to {auto_volt_range:0.1e} V."
    )


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
