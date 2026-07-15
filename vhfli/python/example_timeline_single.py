# Copyright 2026 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to use the Timeline module in the Zurich Instruments LabOne API for Python.

Requirements:
    * LabOne Version >= 26.07
    * Instruments:
        1 x VHFLI with AWG option installed and a loopback BNC cable between Signal Output 1 +V and Signal Input 1 +V of the device.

Usage:
    example_timeline_single.py [options] <device_id>
    example_timeline_single.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: VHFLI]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    -i --device_interface IF  Interface of the device [default: 1GbE]

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne API User Manual to learn how to obtain the JSON string from the LabOne User Interface:
https://docs.zhinst.com/labone_api_user_manual/modules/timeline
"""

import zhinst.core as zi
import matplotlib.pyplot as plt
import time


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    device_interface: str = "1GbE",
):
    """run the example."""

    ### Establish connection to the data server and the instrument
    daq = zi.ziDAQServer(server_host, server_port, 6)
    daq.connectDevice(device_id, device_interface)
    device_type = daq.getString(f"/{device_id}/features/devtype")
    print(
        f"Established connection to device {device_id.upper()} of type {device_type}."
    )
    print(f"Client version: {daq.version()}")
    print(f"Server version: {daq.getString('/zi/about/version')}")
    device_options = daq.getString(f"/{device_id}/features/options")
    if "AWG" not in device_options:
        print(
            f"This example requires the AWG option, but it is not installed on device {device_id.upper()}."
        )
        daq.disconnect()
        print("Disconnected the API session.")
        return

    """ Configure the device """

    ### Configure the instrument for the Timeline experiment
    device_settings = [
        (f"/{device_id}/oscs/0/freq", 40e6),
        (f"/{device_id}/sigouts/0/generators/*/enable", 0),
        (f"/{device_id}/generators/3/oscselect", 0),
        (f"/{device_id}/sigouts/0/range", 0.5),
        (f"/{device_id}/sigouts/0/on", 1),
        (f"/{device_id}/sigins/0/range", 0.5),
        (f"/{device_id}/sigins/0/imp50", 1),
        (f"/{device_id}/sigins/0/on", 1),
        (f"/{device_id}/demods/0/adcselect", 0),
        (f"/{device_id}/demods/0/oscselect", 0),
        (f"/{device_id}/demods/0/phaseshift", 90),
        (f"/{device_id}/demods/0/bypass", 1),
    ]
    daq.set(device_settings)

    # Time difference in seconds between two consecutive timestamp ticks
    dt = daq.getDouble(f"/{device_id}/system/properties/timebase")

    ### Carry out measurement with the Timeline module
    data = timeline_module_measurement(daq, device_id)

    ### Disconnect from the data server
    daq.disconnect()
    print("Disconnected the API session.")

    ### Post-process the acquired data and plot the results
    process_and_plot_data(data, device_id, dt)


def timeline_module_measurement(daq, device_id):
    ### Create a Timeline module instance
    tlm = daq.timelineModule()
    tlm.set("device", device_id)

    ### Enable pulse modulation in the Signal Output port
    tlm.set("sigouts/0/modulation/type", "complex")

    ### Apply a JSON string to the Timeline module to define the experiment sequence
    ### To obtain the JSON string from the LabOne User Interface, check the LabOne API User Manual
    json_string = """{
        "meta": {
            "schemaVersion": "1.0.0"
        },
        "block": {
            "type": "block",
            "iterations": 1,
            "sequence": [
                {
                    "type": "section",
                    "minDuration": 0,
                    "signals": {
                        "sigout0": [
                            {
                                "type": "delay",
                                "duration": 6.4e-8
                            },
                            {
                                "type": "pulse",
                                "waveform": "gauss",
                                "amplitude": 4e-1,
                                "peak": 5e-1,
                                "width": 1.25e-1,
                                "duration": 4.0e-7
                            },
                            {
                                "type": "delay",
                                "duration": 9.6e-8
                            },
                            {
                                "type": "pulse",
                                "waveform": "drag",
                                "amplitude": 4e-1,
                                "peak": 5e-1,
                                "width": 1.25e-1,
                                "duration": 3.04e-7
                            },
                            {
                                "type": "delay",
                                "duration": 2.08e-7
                            }
                        ],
                        "demod0": [
                            {
                                "type": "delay",
                                "duration": 3.04e-7
                            },
                            {
                                "type": "measurement",
                                "rate": 5e7,
                                "duration": 1.04e-6
                            }
                        ]
                    }
                }
            ]
        }
    }"""
    tlm.set("sequence/sourcestring", json_string)

    ### Subscribe to the relevant signal paths for data acquisition
    signal_paths = [
        f"/{device_id}/demods/0/sample.x",
        f"/{device_id}/demods/0/sample.y",
        f"/{device_id}/demods/0/sample.r",
    ]
    tlm.subscribe(signal_paths)

    ### Execute the Timeline sequence and monitor its progress
    print("Starting Timeline execution...")
    tlm.execute()
    timeout_sec = 10.0
    start = time.time()
    while not tlm.finished():
        if time.time() - start > timeout_sec:
            tlm.finish()
            print("Timeout occurred.")
            break
        time.sleep(0.5)
        print(f"Progress: {tlm.progress()[0] * 100:.0f}%\r")
    print(f"Timeline execution finished with {tlm.progress()[0] * 100:.0f}% progress.")

    ### Read the acquired data and unsubscribe from the signal paths
    data = tlm.read(flat=True)
    tlm.unsubscribe("*")

    ### Tear down the Timeline module
    tlm.clear()

    ### Return the acquired data for further processing
    return data


### Post-process the acquired data and plot the results
def process_and_plot_data(data, device_id, dt):
    ### Extract the acquired signal paths from the data dictionary
    acquired_signal_paths = [
        key for key in data.keys() if key.startswith(f"/{device_id}/")
    ]
    if not acquired_signal_paths:
        print("No data acquired.")
        return

    ### Extract the signal values and timestamps from the acquired data
    signals = {}
    for path in acquired_signal_paths:
        signals[path] = data[path][0]["value"][0]
    ts = data[acquired_signal_paths[0]][0]["timestamp"][0]
    t = (ts - ts[0]) * dt

    ### Plot the acquired signals against time
    print("Displaying the results in the plot...")
    fig = plt.figure(figsize=(8, 6))
    fig.suptitle("Timeline Module Measurement Results")
    for path in acquired_signal_paths:
        plt.plot(t * 1e6, signals[path] * 1e3, label=path)
    plt.xlabel("time (μs)")
    plt.ylabel("amplitude (mV)")
    plt.legend()
    plt.grid()
    plt.show()
    print("Done.")


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
