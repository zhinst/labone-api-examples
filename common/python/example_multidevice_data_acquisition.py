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
    * Signal Out 1 of the master device is split into Signal In 1 of the master
      and slave.

Usage:
    example_multidevice_data_acquisition.py [options] <device_id_master> <device_ids_slave>...
    example_multidevice_data_acquisition.py -h | --help

Arguments:
    <device_id_master>  The ID of the master device [device_type: .*LI]
    <device_ids_slave>  The IDs of the slave devices [device_type: .*LI]

Options:
    -h --help         Show this screen.
    -s --synchronize  Multi-device synchronization will be started and
                      stopped before and after the data acquisition
    -p --plot         create a plot.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the "LabOne Programming Manual" for further help, available:
    - On Windows via the Start-Menu:
    Programs -> Zurich Instruments -> Documentation
    - On Linux in the LabOne .tar.gz archive in the "Documentation"
    sub-folder.
"""

import time
import zhinst.utils
import zhinst.ziPython
import matplotlib.pyplot as plt


def run_example(
    device_id_master: str,
    device_ids_slave: list,
    plot: bool = False,
    synchronize: bool = True,
):
    """run the example."""

    # Connection to the data server and devices
    # Connection to the local server 'localhost' ^= '127.0.0.1'
    apilevel = 6
    daq = zhinst.ziPython.ziDAQServer("localhost", 8004, apilevel)
    discovery = zhinst.ziPython.ziDiscovery()

    props = []
    # Master ID
    device_serial = discovery.find(device_id_master).lower()
    props.append(discovery.get(device_serial))
    # Slave IDs
    for device_id in device_ids_slave:
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

    # Master device settings
    master = props[0]["deviceid"].lower()
    daq.setInt("/%s/sigouts/%d/on" % (master, out_c), 1)
    daq.setDouble("/%s/sigouts/%d/range" % (master, out_c), 1)
    daq.setDouble(
        "/%s/sigouts/%d/amplitudes/%d" % (master, out_c, out_mixer_c), out_amp
    )
    daq.setDouble("/%s/demods/%d/phaseshift" % (master, demod_c), 0)
    daq.setInt("/%s/demods/%d/order" % (master, demod_c), filter_order)
    daq.setDouble("/%s/demods/%d/rate" % (master, demod_c), demod_rate)
    daq.setInt("/%s/demods/%d/harmonic" % (master, demod_c), 1)
    daq.setInt("/%s/demods/%d/enable" % (master, demod_c), 1)
    daq.setInt("/%s/demods/%d/oscselect" % (master, demod_c), osc_c)
    daq.setInt("/%s/demods/%d/adcselect" % (master, demod_c), in_c)
    daq.setDouble("/%s/demods/%d/timeconstant" % (master, demod_c), time_constant)
    daq.setDouble("/%s/oscs/%d/freq" % (master, osc_c), osc_freq)
    daq.setInt("/%s/sigins/%d/imp50" % (master, in_c), 1)
    daq.setInt("/%s/sigins/%d/ac" % (master, in_c), 0)
    daq.setDouble("/%s/sigins/%d/range" % (master, in_c), out_amp / 2)
    daq.setDouble("/%s/sigouts/%d/enables/%d" % (master, out_c, out_mixer_c), 0)
    # Slave device settings
    for prop in props[1:]:
        slave = prop["deviceid"].lower()
        daq.setDouble("/%s/demods/%d/phaseshift" % (slave, demod_c), 0)
        daq.setInt("/%s/demods/%d/order" % (slave, demod_c), filter_order)
        daq.setDouble("/%s/demods/%d/rate" % (slave, demod_c), demod_rate)
        daq.setInt("/%s/demods/%d/harmonic" % (slave, demod_c), 1)
        daq.setInt("/%s/demods/%d/enable" % (slave, demod_c), 1)
        daq.setInt("/%s/demods/%d/oscselect" % (slave, demod_c), osc_c)
        daq.setInt("/%s/demods/%d/adcselect" % (slave, demod_c), in_c)
        daq.setDouble("/%s/demods/%d/timeconstant" % (slave, demod_c), time_constant)
        daq.setDouble("/%s/oscs/%d/freq" % (slave, osc_c), osc_freq)
        daq.setInt("/%s/sigins/%d/imp50" % (slave, in_c), 1)
        daq.setInt("/%s/sigins/%d/ac" % (slave, in_c), 0)
        daq.setDouble("/%s/sigins/%d/range" % (slave, in_c), out_amp / 2)
    # Synchronization
    daq.sync()
    time.sleep(1)

    #  measuring the transient state of demodulator filters using DAQ module

    # DAQ module
    # Create a Data Acquisition Module instance, the return argument is a handle to the module
    daq_module = daq.dataAcquisitionModule()
    # Configure the Data Acquisition Module
    # Device on which trigger will be performed
    daq_module.set("device", master)
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
    triggernode = "/%s/demods/%d/sample.r" % (master, demod_c)
    daq_module.set("triggernode", triggernode)
    #   edge:
    #     POS_EDGE = 1
    #     NEG_EDGE = 2
    #     BOTH_EDGE = 3
    daq_module.set("edge", 1)
    demod_rate = daq.getDouble("/%s/demods/%d/rate" % (master, demod_c))
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
    master_subscribe_node = "/%s/demods/%d/sample.r" % (master, demod_c)
    daq_module.subscribe(master_subscribe_node)
    for prop in props[1:]:
        slave_subscribe_node = "/%s/demods/%d/sample.r" % (prop["deviceid"], demod_c)
        daq_module.subscribe(slave_subscribe_node)

    # Execute the module
    daq_module.execute()
    # Send a trigger
    daq.setDouble("/%s/sigouts/%d/enables/%d" % (master, out_c, out_mixer_c), 1)

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
    daq.setDouble("/%s/sigouts/%d/enables/%d" % (master, out_c, out_mixer_c), 0)
    # Finish the DAQ module
    daq_module.finish()

    #  Extracting and plotting the data

    if plot:

        # Master data
        master_clockbase = daq.getDouble("/%s/clockbase" % master)
        timestamp = result[master_subscribe_node][0]["timestamp"]
        master_time = (timestamp[0] - float(timestamp[0][0])) / master_clockbase
        demod_r_master = result[master_subscribe_node][0]["value"][0]
        # Plotting
        _, (axis1, axis2) = plt.subplots(2)
        axis1.plot(master_time * 1e3, demod_r_master * 1e3, color="blue")
        axis1.set_ylabel("Amplitude [mV]", fontsize=12, color="k")
        axis1.legend(["Master"])
        axis1.set_title("Transient Measurement by DAQ Module")
        axis1.grid(True)

        # Slave data
        for prop in props[1:]:
            slave = prop["deviceid"].lower()
            slave_subscribe_node = "/%s/demods/%d/sample.r" % (slave, demod_c)
            slave_clockbase = daq.getDouble("/%s/clockbase" % slave)
            slave_timestamp = result[slave_subscribe_node][0]["timestamp"]
            slave_time = (
                slave_timestamp[0] - float(slave_timestamp[0][0])
            ) / slave_clockbase
            slave_demod_r = result[slave_subscribe_node][0]["value"][0]

            axis2 = plt.subplot(2, 1, 2)
            axis2.plot(slave_time * 1e3, slave_demod_r * 1e3, color="red")
            axis2.legend(["Slaves"])
            axis2.set_xlabel("Time [ms]", fontsize=12, color="k")
            axis2.set_ylabel("Amplitude [mV]", fontsize=12, color="k")
            axis2.grid(True)

        fig, (axis1, axis2) = plt.subplots(2)
        axis1.plot(master_time * 1e3, demod_r_master * 1e3, color="blue")

        for prop in props[1:]:
            slave = prop["deviceid"].lower()
            slave_subscribe_node = "/%s/demods/%d/sample.r" % (slave, demod_c)
            slave_clockbase = daq.getDouble("/%s/clockbase" % slave)
            slave_timestamp = result[slave_subscribe_node][0]["timestamp"]
            slave_time = (
                slave_timestamp[0] - float(slave_timestamp[0][0])
            ) / slave_clockbase
            slave_demod_r = result[slave_subscribe_node][0]["value"][0]
            axis1.plot(slave_time * 1e3, slave_demod_r * 1e3, color="red")
        axis1.set_ylabel("Amplitude [mV]", fontsize=12, color="k")
        axis1.legend(["Master", "Slaves"])
        axis1.set_title("Transient Measurement by DAQ Module")
        axis1.grid(True)

        for prop in props[1:]:
            slave = prop["deviceid"].lower()
            slave_subscribe_node = "/%s/demods/%d/sample.r" % (slave, demod_c)
            slave_clockbase = daq.getDouble("/%s/clockbase" % slave)
            slave_timestamp = result[slave_subscribe_node][0]["timestamp"]
            slave_time = (
                slave_timestamp[0] - float(slave_timestamp[0][0])
            ) / slave_clockbase
            axis2.plot(
                slave_time * 1e3, (master_time - slave_time) * 1e3, color="green"
            )
        axis2.set_title("Time Difference between Master and Slaves")
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
