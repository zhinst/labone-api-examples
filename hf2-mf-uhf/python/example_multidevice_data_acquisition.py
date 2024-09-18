# Copyright 2008 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to synchronize 2 or more MFLI instruments or 2 or more UHFLI
instruments using the MDS capability of LabOne.
It also measures the temporal response of demodulator filters of both
both instruments using the Data Acquisition (DAQ) Module.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        2+ x Lock-in Instrument
    * The cabling of the instruments must follow the MDS cabling depicted in the
      MDS tab of LabOne.
    * Signal Out 1 of the leader device is split into Signal In 1 of the leader
      and follower.

Usage:
    example_multidevice_data_acquisition.py [options] <device_id_leader> <device_ids_follower>...
    example_multidevice_data_acquisition.py -h | --help

Arguments:
    <device_id_leader>  The ID of the leader device [device_type: .*LI]
    <device_ids_follower>  The IDs of the follower devices [device_type: .*LI]

Options:
    -h --help              Show this screen.
    -s --server_host IP    Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT  Port number of the data server [default: None]
    --hf2                  Flag if the used device is an HF2 instrument. (Since the HF2 uses
                           a different data server and support only API level 1
                           it requires minor tweaking) [default = False]
    --synchronize          Multi-device synchronization will be started and
                           stopped before and after the data acquisition
    --no-plot              Hide plot of the recorded data.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import zhinst.utils
import zhinst.core
import matplotlib.pyplot as plt


def run_example(
    device_id_leader: str,
    device_ids_follower: list,
    server_host: str = "localhost",
    server_port: int = None,
    hf2: bool = False,
    plot: bool = True,
    synchronize: bool = True,
):
    """run the example."""

    apilevel_example = 1 if hf2 else 6  # The API level supported by this example.
    if not server_port:
        server_port = 8005 if hf2 else 8004
    daq = zhinst.core.ziDAQServer(server_host, server_port, apilevel_example)
    discovery = zhinst.core.ziDiscovery()

    props = []
    # Leader ID
    device_serial = discovery.find(device_id_leader).lower()
    props.append(discovery.get(device_serial))
    # Follower IDs
    for device_id in device_ids_follower:
        device_serial = discovery.find(device_id).lower()
        props.append(discovery.get(device_serial))
    devices = props[0]["deviceid"]
    for prop in props[1:]:
        devices += "," + prop["deviceid"]
    # Switching between MFLI and UHFLI
    device_type = props[0]["devicetype"]
    for prop in props[1:]:
        if prop["devicetype"] != device_type:
            raise Exception(
                "This example needs 2 or more MFLI instruments or 2 or more UHFLI instruments."
                "Mixing device types is not possible"
            )

    for prop in props:
        if prop["devicetype"] == "UHFLI":
            daq.connectDevice(prop["deviceid"], prop["interfaces"][0])
        else:
            daq.connectDevice(prop["deviceid"], "1GbE")

    # Disable all available outputs, demods, ...
    for prop in props:
        zhinst.utils.disable_everything(daq, prop["deviceid"])

    #  Device synchronization
    if synchronize:
        print("Synchronizing devices %s ...\n" % devices)
        mds = daq.multiDeviceSyncModule()
        mds.set("start", 0)
        mds.set("group", 0)
        mds.execute()
        mds.set("devices", devices)
        mds.set("start", 1)

        timeout = 20
        start = time.time()
        status = 0
        while status != 2:
            time.sleep(0.2)
            status = mds.getInt("status")
            if status == -1:
                raise Exception("Error during device sync")
            if (time.time() - start) > timeout:
                raise Exception("Timeout during device sync")

        print("Devices successfully synchronized.")

    # Device settings
    demod_c = 0  # demod channel, for paths on the device
    out_c = 0  # signal output channel
    # Get the value of the instrument's default Signal Output mixer channel.
    prop = discovery.get(props[0]["deviceid"])
    out_mixer_c = zhinst.utils.default_output_mixer_channel(prop, out_c)
    in_c = 0  # signal input channel
    osc_c = 0  # oscillator

    time_constant = 1.0e-3  # [s]
    demod_rate = 10e3  # [Sa/s]
    filter_order = 8
    osc_freq = 1e3  # [Hz]
    out_amp = 0.600  # [V]

    # Leader device settings
    leader = props[0]["deviceid"].lower()
    daq.setInt("/%s/sigouts/%d/on" % (leader, out_c), 1)
    daq.setDouble("/%s/sigouts/%d/range" % (leader, out_c), 1)
    daq.setDouble(
        "/%s/sigouts/%d/amplitudes/%d" % (leader, out_c, out_mixer_c), out_amp
    )
    daq.setDouble("/%s/demods/%d/phaseshift" % (leader, demod_c), 0)
    daq.setInt("/%s/demods/%d/order" % (leader, demod_c), filter_order)
    daq.setDouble("/%s/demods/%d/rate" % (leader, demod_c), demod_rate)
    daq.setInt("/%s/demods/%d/harmonic" % (leader, demod_c), 1)
    daq.setInt("/%s/demods/%d/enable" % (leader, demod_c), 1)
    daq.setInt("/%s/demods/%d/oscselect" % (leader, demod_c), osc_c)
    daq.setInt("/%s/demods/%d/adcselect" % (leader, demod_c), in_c)
    daq.setDouble("/%s/demods/%d/timeconstant" % (leader, demod_c), time_constant)
    daq.setDouble("/%s/oscs/%d/freq" % (leader, osc_c), osc_freq)
    daq.setInt("/%s/sigins/%d/imp50" % (leader, in_c), 1)
    daq.setInt("/%s/sigins/%d/ac" % (leader, in_c), 0)
    daq.setDouble("/%s/sigins/%d/range" % (leader, in_c), out_amp / 2)
    daq.setDouble("/%s/sigouts/%d/enables/%d" % (leader, out_c, out_mixer_c), 0)
    # Follower device settings
    for prop in props[1:]:
        follower = prop["deviceid"].lower()
        daq.setDouble("/%s/demods/%d/phaseshift" % (follower, demod_c), 0)
        daq.setInt("/%s/demods/%d/order" % (follower, demod_c), filter_order)
        daq.setDouble("/%s/demods/%d/rate" % (follower, demod_c), demod_rate)
        daq.setInt("/%s/demods/%d/harmonic" % (follower, demod_c), 1)
        daq.setInt("/%s/demods/%d/enable" % (follower, demod_c), 1)
        daq.setInt("/%s/demods/%d/oscselect" % (follower, demod_c), osc_c)
        daq.setInt("/%s/demods/%d/adcselect" % (follower, demod_c), in_c)
        daq.setDouble("/%s/demods/%d/timeconstant" % (follower, demod_c), time_constant)
        daq.setDouble("/%s/oscs/%d/freq" % (follower, osc_c), osc_freq)
        daq.setInt("/%s/sigins/%d/imp50" % (follower, in_c), 1)
        daq.setInt("/%s/sigins/%d/ac" % (follower, in_c), 0)
        daq.setDouble("/%s/sigins/%d/range" % (follower, in_c), out_amp / 2)
    # Synchronization
    daq.sync()
    time.sleep(1)

    #  measuring the transient state of demodulator filters using DAQ module

    # DAQ module
    # Create a Data Acquisition Module instance, the return argument is a handle to the module
    daq_module = daq.dataAcquisitionModule()
    # Configure the Data Acquisition Module
    # Device on which trigger will be performed
    daq_module.set("device", leader)
    # The number of triggers to capture (if not running in endless mode).
    daq_module.set("count", 1)
    daq_module.set("endless", 0)
    # 'grid/mode' - Specify the interpolation method of
    #   the returned data samples.
    #
    # 1 = Nearest. If the interval between samples on the grid does not match
    #     the interval between samples sent from the device exactly, the nearest
    #     sample (in time) is taken.
    #
    # 2 = Linear interpolation. If the interval between samples on the grid does
    #     not match the interval between samples sent from the device exactly,
    #     linear interpolation is performed between the two neighbouring
    #     samples.
    #
    # 4 = Exact. The subscribed signal with the highest sampling rate (as sent
    #     from the device) defines the interval between samples on the DAQ
    #     Module's grid. If multiple signals are subscribed, these are
    #     interpolated onto the grid (defined by the signal with the highest
    #     rate, "highest_rate"). In this mode, duration is
    #     read-only and is defined as num_cols/highest_rate.
    grid_mode = 2
    daq_module.set("grid/mode", grid_mode)
    #   type
    #     NO_TRIGGER = 0
    #     EDGE_TRIGGER = 1
    #     DIGITAL_TRIGGER = 2
    #     PULSE_TRIGGER = 3
    #     TRACKING_TRIGGER = 4
    #     HW_TRIGGER = 6
    #     TRACKING_PULSE_TRIGGER = 7
    #     EVENT_COUNT_TRIGGER = 8
    daq_module.set("type", 1)
    #   triggernode, specify the triggernode to trigger on.
    #     SAMPLE.X = Demodulator X value
    #     SAMPLE.Y = Demodulator Y value
    #     SAMPLE.R = Demodulator Magnitude
    #     SAMPLE.THETA = Demodulator Phase
    #     SAMPLE.AUXIN0 = Auxilliary input 1 value
    #     SAMPLE.AUXIN1 = Auxilliary input 2 value
    #     SAMPLE.DIO = Digital I/O value
    triggernode = "/%s/demods/%d/sample.r" % (leader, demod_c)
    daq_module.set("triggernode", triggernode)
    #   edge:
    #     POS_EDGE = 1
    #     NEG_EDGE = 2
    #     BOTH_EDGE = 3
    daq_module.set("edge", 1)
    demod_rate = daq.getDouble("/%s/demods/%d/rate" % (leader, demod_c))
    # Exact mode: To preserve our desired trigger duration, we have to set
    # the number of grid columns to exactly match.
    trigger_duration = time_constant * 30
    sample_count = demod_rate * trigger_duration
    daq_module.set("grid/cols", sample_count)
    # The length of each trigger to record (in seconds).
    daq_module.set("duration", trigger_duration)
    daq_module.set("delay", -trigger_duration / 4)
    # Do not return overlapped trigger events.
    daq_module.set("holdoff/time", 0)
    daq_module.set("holdoff/count", 0)
    daq_module.set("level", out_amp / 6)
    # The hysterisis is effectively a second criteria (if non-zero) for triggering
    # and makes triggering more robust in noisy signals. When the trigger `level`
    # is violated, then the signal must return beneath (for positive trigger edge)
    # the hysteresis value in order to trigger.
    daq_module.set("hysteresis", 0.01)
    # synchronizing the settings
    daq.sync()

    #  Recording

    # Subscribe to the demodulators
    daq_module.unsubscribe("*")
    leader_subscribe_node = "/%s/demods/%d/sample.r" % (leader, demod_c)
    daq_module.subscribe(leader_subscribe_node)
    for prop in props[1:]:
        follower_subscribe_node = "/%s/demods/%d/sample.r" % (prop["deviceid"], demod_c)
        daq_module.subscribe(follower_subscribe_node)

    # Execute the module
    daq_module.execute()
    # Send a trigger
    daq.setDouble("/%s/sigouts/%d/enables/%d" % (leader, out_c, out_mixer_c), 1)

    # wait for the acquisition to be finished
    timeout = 20
    t0_measurement = time.time()
    while not daq_module.finished():
        if time.time() - t0_measurement > timeout:
            raise Exception(
                f"Timeout after {timeout} s - recording not complete. "
                "Are the streaming nodes enabled? "
                "Has a valid signal_path been specified?"
            )
        time.sleep(1)
        print(f"Progress {daq_module.progress()[0]:.2%}", end="\r")

    # Read the result
    result = daq_module.read(True)

    # Turn off the trigger
    daq.setDouble("/%s/sigouts/%d/enables/%d" % (leader, out_c, out_mixer_c), 0)
    # Finish the DAQ module
    daq_module.finish()

    #  Extracting and plotting the data

    if plot:

        # Leader data
        leader_clockbase = daq.getDouble("/%s/clockbase" % leader)
        timestamp = result[leader_subscribe_node][0]["timestamp"]
        leader_time = (timestamp[0] - float(timestamp[0][0])) / leader_clockbase
        demod_r_leader = result[leader_subscribe_node][0]["value"][0]
        # Plotting
        _, (axis1, axis2) = plt.subplots(2)
        axis1.plot(leader_time * 1e3, demod_r_leader * 1e3, color="blue")
        axis1.set_ylabel("Amplitude [mV]", fontsize=12, color="k")
        axis1.legend(["Leader"])
        axis1.set_title("Transient Measurement by DAQ Module")
        axis1.grid(True)

        # Follower data
        for prop in props[1:]:
            follower = prop["deviceid"].lower()
            follower_subscribe_node = "/%s/demods/%d/sample.r" % (follower, demod_c)
            follower_clockbase = daq.getDouble("/%s/clockbase" % follower)
            follower_timestamp = result[follower_subscribe_node][0]["timestamp"]
            follower_time = (
                follower_timestamp[0] - float(follower_timestamp[0][0])
            ) / follower_clockbase
            follower_demod_r = result[follower_subscribe_node][0]["value"][0]

            axis2 = plt.subplot(2, 1, 2)
            axis2.plot(follower_time * 1e3, follower_demod_r * 1e3, color="red")
            axis2.legend(["Followers"])
            axis2.set_xlabel("Time [ms]", fontsize=12, color="k")
            axis2.set_ylabel("Amplitude [mV]", fontsize=12, color="k")
            axis2.grid(True)

        fig, (axis1, axis2) = plt.subplots(2)
        axis1.plot(leader_time * 1e3, demod_r_leader * 1e3, color="blue")

        for prop in props[1:]:
            follower = prop["deviceid"].lower()
            follower_subscribe_node = "/%s/demods/%d/sample.r" % (follower, demod_c)
            follower_clockbase = daq.getDouble("/%s/clockbase" % follower)
            follower_timestamp = result[follower_subscribe_node][0]["timestamp"]
            follower_time = (
                follower_timestamp[0] - float(follower_timestamp[0][0])
            ) / follower_clockbase
            follower_demod_r = result[follower_subscribe_node][0]["value"][0]
            axis1.plot(follower_time * 1e3, follower_demod_r * 1e3, color="red")
        axis1.set_ylabel("Amplitude [mV]", fontsize=12, color="k")
        axis1.legend(["Leader", "Followers"])
        axis1.set_title("Transient Measurement by DAQ Module")
        axis1.grid(True)

        for prop in props[1:]:
            follower = prop["deviceid"].lower()
            follower_subscribe_node = "/%s/demods/%d/sample.r" % (follower, demod_c)
            follower_clockbase = daq.getDouble("/%s/clockbase" % follower)
            follower_timestamp = result[follower_subscribe_node][0]["timestamp"]
            follower_time = (
                follower_timestamp[0] - float(follower_timestamp[0][0])
            ) / follower_clockbase
            axis2.plot(
                follower_time * 1e3, (leader_time - follower_time) * 1e3, color="green"
            )
        axis2.set_title("Time Difference between Leader and Followers")
        axis2.set_xlabel("Time [ms]", fontsize=12, color="k")
        axis2.set_ylabel("Time difference [ms]", fontsize=12, color="k")
        axis2.grid(True)

        fig.set_tight_layout(True)

        plt.show()

    return result


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
