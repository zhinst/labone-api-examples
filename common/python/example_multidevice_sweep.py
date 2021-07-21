# Copyright 2018 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Demonstrate how to perform a frequency sweep on two synchronized devices using
the MultiDeviceSync Module and ziDAQSweeper class/Sweeper Module.

Perform a frequency sweep on two devices and record
demodulator data using ziPython's ziDAQSweeper module. The devices are first
synchronized using the MultiDeviceSync Module, then the sweep is executed
before stopping the synchronization.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        2+ x Lock-in Instrument
    * The cabling of the instruments must follow the MDS cabling depicted in the
      MDS tab of LabOne.
    * Signal Out 1 of the master device is split into Signal In 1 of the master
      and slave.

Usage:
    example_multidevice_sweep.py [options] <device_id_master> <device_ids_slave>...
    example_multidevice_sweep.py -h | --help

Arguments:
    <device_id_master>  The ID of the master device [device_type: UHFLI|MF|HF2]
    <device_ids_slave>  The IDs of the slave devices [device_type: UHFLI|MF|HF2]

Options:
    -h --help                Show this screen.
    -a --amplitude AMPLITUDE  The amplitude to set on the signal output. [default: 0.1]
    -s --synchronize         Multi-device synchronization will be started and
                             stopped before and after the sweep
    --no-plot                Hide plot of the recorded data.
    --save                   Saves the data to file.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import zhinst.utils
import matplotlib.pyplot as plt


def run_example(
    device_id_master: str,
    device_ids_slave: list,
    amplitude: float = 0.1,
    plot: bool = True,
    synchronize: bool = True,
    save: bool = False,
):
    """run the example."""

    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    # This example can't run with HF2 Instruments or instruments without the DIG option.
    apilevel_example = 6  # The API level supported by this example.
    required_devtype = r"UHFLI|MF|HF2"  # Regular expression of supported instruments.
    required_options = {}  # No special options required.
    required_err_msg = "This example requires HF2, UHFLI or MF instruments."
    (daq, device, _) = zhinst.utils.create_api_session(
        device_id_master,
        apilevel_example,
        required_devtype=required_devtype,
        required_options=required_options,
        required_err_msg=required_err_msg,
    )

    device_ids = [device_id_master] + device_ids_slave

    print(device_ids)

    for device in device_ids:
        daq.connectDevice(device, "1GbE")
    daq.sync()

    zhinst.utils.api_server_version_check(daq)

    # Create a base configuration on all devices:
    # Disable all available outputs, awgs, demods, scopes,...
    for device in device_ids:
        zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all device configurations. The values below may be
    # changed if the instrument has multiple input/output channels and/or either
    # the Multifrequency or Multidemodulator options installed.
    out_channel = 0
    out_mixer_channel = 0
    in_channel = 0
    demod_index = 0
    osc_index = 0
    demod_rate = 10e3
    time_constant = 0.01
    for device in device_ids:
        exp_setting = [
            ["/%s/sigins/%d/ac" % (device, in_channel), 0],
            ["/%s/sigins/%d/range" % (device, in_channel), 2 * amplitude],
            ["/%s/demods/%d/enable" % (device, demod_index), 1],
            ["/%s/demods/%d/rate" % (device, demod_index), demod_rate],
            ["/%s/demods/%d/adcselect" % (device, demod_index), in_channel],
            ["/%s/demods/%d/order" % (device, demod_index), 4],
            ["/%s/demods/%d/timeconstant" % (device, demod_index), time_constant],
            ["/%s/demods/%d/oscselect" % (device, demod_index), osc_index],
            ["/%s/demods/%d/harmonic" % (device, demod_index), 1],
            ["/%s/sigouts/%d/on" % (device, out_channel), 1],
            ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
            ["/%s/sigouts/%d/range" % (device, out_channel), 2 * amplitude],
            [
                "/%s/sigouts/%d/amplitudes/%d"
                % (device, out_channel, out_mixer_channel),
                amplitude,
            ],
        ]
        daq.set(exp_setting)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that 1. the settings have taken effect on the device before issuing
    # the poll() command and 2. clear the API's data buffers.
    daq.sync()

    # prepare devices string to tell the sync module which devices should be synchronized
    # (should not contain spaces)
    devices = device_ids[0]
    for device in device_ids[1:]:
        devices += "," + device

    # Here we synchronize all the devices as defined in the comma separated string "devices"
    if synchronize:
        print("Synchronizing")
        md_sync_module = daq.multiDeviceSyncModule()
        md_sync_module.set("start", 0)
        md_sync_module.set("group", 0)
        md_sync_module.execute()
        md_sync_module.set("devices", devices)
        md_sync_module.set("start", 1)

        timeout = 10
        tstart = time.time()
        while True:
            time.sleep(0.2)
            status = md_sync_module.getInt("status")
            assert status != -1, "Error during device sync"
            if status == 2:
                break
            assert time.time() - tstart < timeout, "Timeout during device sync"

    print("Start sweeper")
    # Create an instance of the Sweeper Module (ziDAQSweeper class).
    sweeper = daq.sweep()
    # Configure the Sweeper Module's parameters.
    # Set the device that will be used for the sweep - this parameter must be set.
    sweeper.set("device", device_ids[0])
    # Specify the `gridnode`: The instrument node that we will sweep, the device
    # setting corresponding to this node path will be changed by the sweeper.
    sweeper.set("gridnode", "oscs/%d/freq" % osc_index)
    # Set the `start` and `stop` values of the gridnode value interval we will use in the sweep.
    sweeper.set("start", 100)
    sweeper.set("stop", 500e3)
    # Set the number of points to use for the sweep, the number of gridnode
    # setting values will use in the interval (`start`, `stop`).
    samplecount = 100
    sweeper.set("samplecount", samplecount)
    # Specify logarithmic spacing for the values in the sweep interval.
    sweeper.set("xmapping", 1)
    # Automatically control the demodulator bandwidth/time constants used.
    # 0=manual, 1=fixed, 2=auto
    # Note: to use manual and fixed, bandwidth has to be set to a value > 0.
    sweeper.set("bandwidthcontrol", 2)
    # Sets the bandwidth overlap mode (default 0). If enabled, the bandwidth of
    # a sweep point may overlap with the frequency of neighboring sweep
    # points. The effective bandwidth is only limited by the maximal bandwidth
    # setting and omega suppression. As a result, the bandwidth is independent
    # of the number of sweep points. For frequency response analysis bandwidth
    # overlap should be enabled to achieve maximal sweep speed (default: 0). 0 =
    # Disable, 1 = Enable.
    sweeper.set("bandwidthoverlap", 0)

    # Sequential scanning mode (as opposed to binary or bidirectional).
    sweeper.set("scan", 0)
    # We don't require a fixed settling/time since there is no DUT
    # involved in this example's setup (only a simple feedback cable), so we set
    # this to zero. We need only wait for the filter response to settle,
    # specified via settling/inaccuracy.
    sweeper.set("settling/time", 0)
    # The settling/inaccuracy' parameter defines the settling time the
    # sweeper should wait before changing a sweep parameter and recording the next
    # sweep data point. The settling time is calculated from the specified
    # proportion of a step response function that should remain. The value
    # provided here, 0.001, is appropriate for fast and reasonably accurate
    # amplitude measurements. For precise noise measurements it should be set to
    # ~100n.
    # Note: The actual time the sweeper waits before recording data is the maximum
    # time specified by settling/time and defined by settling/inaccuracy.
    sweeper.set("settling/inaccuracy", 0.001)
    # Set the minimum time to record and average data to 10 demodulator
    # filter time constants.
    sweeper.set("averaging/tc", 10)
    # Minimal number of samples that we want to record and average is 100. Note,
    # the number of samples used for averaging will be the maximum number of
    # samples specified by either averaging/tc or averaging/sample.
    sweeper.set("averaging/sample", 10)

    # Now subscribe to the nodes from which data will be recorded. Note, this is
    # not the subscribe from ziDAQServer; it is a Module subscribe. The Sweeper
    # Module needs to subscribe to the nodes it will return data for.x
    paths = []
    for device in device_ids:
        paths.append("/%s/demods/%d/sample" % (device, demod_index))
    for path in paths:
        sweeper.subscribe(path)

    # Set the filename stem for saving the data to file. The data are saved in a separate
    # numerically incrementing sub-directory prefixed with the /save/filename value each
    # time a save command is issued.
    # The base directory is specified with the save/directory parameter. The default is
    # C:\Users\richardc\Documents\Zurich Instruments\LabOne\WebServer on Windows.
    # On linux $HOME/Zurich Instruments/LabOne/WebServer
    sweeper.set("save/filename", "sweep_with_save")
    # Set the file format to use.
    # 0 = MATLAB, 1 = CSV, 2 = ZView (if instrument has impedance option), 4 = HDF5
    # sweeper.set("save/fileformat", 4)
    # Alternatively you can pass one of the strings "mat", "csv", "zview" or "hdf5" to
    # the set command.
    sweeper.set("save/fileformat", "hdf5")

    # Start the Sweeper running.
    sweeper.execute()

    start = time.time()
    timeout = 60  # [s]
    while not sweeper.finished():  # Wait until the sweep is complete, with timeout.
        time.sleep(0.5)
        progress = sweeper.progress()
        print(f"Individual sweep progress: {progress[0]:.2%}.", end="\n")
        # Here we could read intermediate data via:
        # data = sweeper.read(True)...
        # and process it while the sweep is completing.
        # if device in data:
        # ...
        if (time.time() - start) > timeout:
            # If for some reason the sweep is blocking, force the end of the
            # measurement.
            print("\nSweep still not finished, forcing finish...")
            sweeper.finish()
    print("")

    if save:
        # Indicate that the data should be saved to file.
        # This must be done before the read() command.
        # Otherwise there is no longer any data to save.
        sweeper.set("save/save", save)
        # Wait until the save is complete. The saving is done asynchronously in the background
        # so we need to wait until it is complete. In the case of the sweeper it is important
        # to wait for completion before before performing the module read command. The sweeper has
        # a special fast read command which could otherwise be executed before the saving has
        # started.
        save_done = sweeper.getInt("save/save")
        while save_done != 0:
            save_done = sweeper.getInt("save/save")

    # Read the sweep data. This command can also be executed whilst sweeping
    # (before finished() is True), in this case sweep data up to that time point
    # is returned. It's still necessary still need to issue read() at the end to
    # fetch the rest.
    return_flat_dict = True
    data = sweeper.read(return_flat_dict)
    for path in paths:
        sweeper.unsubscribe(path)

    # Check the dictionary returned is non-empty.
    assert (
        data
    ), "read() returned an empty data dictionary, did you subscribe to any paths?"
    # Note: data could be empty if no data arrived, e.g., if the demods were
    # disabled or had rate 0.
    for path in paths:
        assert path in data, (
            "No sweep data in data dictionary: it has no key '%s'" % path
        )

    if plot:

        _, axis = plt.subplots()

        for path in paths:
            samples = data[path]
            for sample in samples:
                axis.plot(sample[0]["frequency"], sample[0]["r"])

        axis.set_title("Results from %d devices." % len(device_ids))
        axis.grid(True)
        axis.set_xlabel("Frequency ($Hz$)")
        axis.set_ylabel(r"Demodulator R ($V_\mathrm{RMS}$)")
        axis.set_xscale("log")

        plt.draw()
        plt.show()

    if synchronize:
        print("Teardown: Clearing the multiDeviceSyncModule.")
        md_sync_module.set("start", 0)
        timeout = 2
        tstart = time.time()
        while True:
            time.sleep(0.1)
            status = md_sync_module.getInt("status")
            assert status != -1, "Error during device sync stop"
            if status == 0:
                break
            if time.time() - tstart > timeout:
                print(
                    "Warning: Timeout during device sync stop. \
                        The devices might still be synchronized."
                )
                break

    return data


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
