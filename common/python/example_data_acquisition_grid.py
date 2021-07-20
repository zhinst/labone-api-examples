# Copyright 2016 Zurich Instruments AG

"""
Zurich Instruments LabOne Python API Example

Python API Example for the Data Acquisition Module in Grid
Mode. Record demodulator sample data using a Software Edge Trigger in Grid Mode
via ziDAQ's 'record' module from the device specified by DEVICE_ID, e.g.,
'dev2006' or 'uhf-dev2006'.

The Data Acquisition Module implements software triggering which operates
analogously to the types of triggering found in laboratory oscilloscopes. The
Data Acquisition Module has a non-blocking (asynchronous) interface, it starts it's
own thread to communicate with the data server.

Grid Mode enables interpolation of the triggered data onto the specified columns
of the grid and alignment of (num_rows) multiple triggers into the rows of the
grid. This example demonstrates basic Grid Mode usage without averaging.

This example records the demodulator data as is - essentially a constant value
with noise. The Data Acquisition Module's 'find' functionality calculates an appropriate
trigger level to record triggers using an edge trigger.

Note:
This example requires a feedback cable between Signal Output 1 and Signal
Input 1 and changes the signal output's amplitude in order to create a signal
upon which to trigger.

Requirements:
    * LabOne Version >= 20.02
    * Instruments:
        1 x Instrument with demodulators
    * signal output 1 connected to signal input 1 with a BNC cable.

Usage:
    example_data_acquisition_grid.py [options] <device_id>
    example_data_acquisition_grid.py -h | --help

Arguments:
    <device_id>  The ID of the device [device_type: .*LI|.*IA|.*IS]

Options:
    -h --help                 Show this screen.
    -s --server_host IP       Hostname or IP address of the dataserver [default: localhost]
    -p --server_port PORT     Port number of the data server [default: 8004]
    -a --amplitude AMPLITUDE  The amplitude to set on the signal output. [default: 0.25]
    -r --num_grids NUM        The number of grids to record. [default: 3]
    --no-plot                 Hide plot of the recorded data.

Raises:
    Exception     If the specified devices do not match the requirements.
    RuntimeError  If the devices is not "discoverable" from the API.

See the LabOne Programming Manual for further help:
https://docs.zhinst.com/labone_programming_manual/
"""

import time
import numpy as np
import zhinst.utils
import matplotlib.pyplot as plt


def run_example(
    device_id: str,
    server_host: str = "localhost",
    server_port: int = 8004,
    amplitude: float = 0.25,
    num_grids: int = 3,
    plot: bool = True,
):
    """run the example."""

    apilevel_example = 6  # The API level supported by this example.
    # Call a zhinst utility function that returns:
    # - an API session `daq` in order to communicate with devices via the data server.
    # - the device ID string that specifies the device branch in the server's node hierarchy.
    # - the device's discovery properties.
    err_msg = "This example only supports instruments with demodulators."
    (daq, device, props) = zhinst.utils.create_api_session(
        device_id, apilevel_example, server_host=server_host, server_port=server_port
    )
    zhinst.utils.api_server_version_check(daq)

    # Enable ziPython's log, the lower the level the more verbose.
    daq.setDebugLevel(3)

    # Create a base configuration: Disable all available outputs, awgs, demods, scopes,...
    zhinst.utils.disable_everything(daq, device)

    # Now configure the instrument for this experiment. The following channels
    # and indices work on all device configurations. The values below may be
    # changed if the instrument has multiple input/output channels and/or either
    # the Multifrequency or Multidemodulator options installed.
    out_channel = 0
    out_mixer_channel = zhinst.utils.default_output_mixer_channel(props)
    in_channel = 0
    trigger_demod_index = 0
    osc_index = 0
    demod_rate = 100e3
    demod_order = 4
    demod_bandwidth = 10e3
    timeconstant = zhinst.utils.bw2tc(demod_bandwidth, demod_order)
    frequency = 400e3
    exp_setting = [
        ["/%s/sigins/%d/ac" % (device, in_channel), 0],
        ["/%s/sigins/%d/imp50" % (device, in_channel), 1],
        ["/%s/sigins/%d/range" % (device, in_channel), 2 * amplitude],
        ["/%s/demods/%d/enable" % (device, trigger_demod_index), 1],
        ["/%s/demods/%d/rate" % (device, trigger_demod_index), demod_rate],
        ["/%s/demods/%d/adcselect" % (device, trigger_demod_index), in_channel],
        ["/%s/demods/%d/order" % (device, trigger_demod_index), demod_order],
        ["/%s/demods/%d/timeconstant" % (device, trigger_demod_index), timeconstant],
        ["/%s/demods/%d/oscselect" % (device, trigger_demod_index), osc_index],
        ["/%s/demods/%d/harmonic" % (device, trigger_demod_index), 1],
        ["/%s/oscs/%d/freq" % (device, osc_index), frequency],
        ["/%s/sigouts/%d/on" % (device, out_channel), 1],
        ["/%s/sigouts/%d/enables/%d" % (device, out_channel, out_mixer_channel), 1],
        ["/%s/sigouts/%d/range" % (device, out_channel), 1],
        [
            "/%s/sigouts/%d/amplitudes/%d" % (device, out_channel, out_mixer_channel),
            amplitude,
        ],
    ]
    daq.set(exp_setting)

    # Wait for the demodulator filter to settle.
    timeconstant_set = daq.getDouble(
        "/%s/demods/%d/timeconstant" % (device, trigger_demod_index)
    )
    time.sleep(10 * timeconstant_set)

    # Perform a global synchronisation between the device and the data server:
    # Ensure that 1. the settings have taken effect on the device before issuing
    # the poll() command and 2. clear the API's data buffers. Note: the sync()
    # must be issued after waiting for the demodulator filter to settle above.
    daq.sync()

    # Create an instance of the Data Acquisition Module.
    daq_module = daq.dataAcquisitionModule()

    # Set the device that will be used for the trigger - this parameter must be set.
    daq_module.set("device", device)
    # We will trigger on a positive edge of a demodulator sample R value.
    # type (int):
    #   NO_TRIGGER = 0
    #   EDGE_TRIGGER = 1
    #   DIGITAL_TRIGGER = 2
    #   PULSE_TRIGGER = 3
    #   TRACKING_TRIGGER = 4
    #   HW_TRIGGER = 6
    #   TRACKING_PULSE_TRIGGER = 7
    #   EVENT_COUNT_TRIGGER = 8
    daq_module.set("type", 1)
    # triggernode (char):
    #   Specify the trigger signal to trigger on. The trigger signal comprises
    #   of a device node path appended with a trigger field seperated by a dot.
    #   For demodulator samples, the following trigger fields are available:
    #   SAMPLE.X = Demodulator X value
    #   SAMPLE.Y = Demodulator Y value
    #   SAMPLE.R = Demodulator Magnitude
    #   SAMPLE.THETA = Demodulator Phase
    #   SAMPLE.AUXIN0 = Auxilliary input 1 value
    #   SAMPLE.AUXIN1 = Auxilliary input 2 value
    #   SAMPLE.DIO = Digital I/O value
    #   SAMPLE.TRIGINN = HW Trigger In N (where supported)
    #   SAMPLE.TRIGOUTN = HW Trigger Out N (where supported)
    #   SAMPLE.TRIGDEMOD1PHASE = Demod 1's oscillator's phase (MF, UHF)
    #   SAMPLE.TRIGDEMOD2PHASE = Demod 2's oscillator's phase (MF)
    #   SAMPLE.TRIGDEMOD4PHASE = Demod 4's oscillator's phase  (UHF)
    #   SAMPLE.TRIGAWGTRIGN = AWG Trigger N  (where supported)
    triggerpath = "/%s/demods/%d/sample.r" % (device, trigger_demod_index)
    triggernode = triggerpath
    daq_module.set("triggernode", triggernode)
    # edge (int):
    #   Specify which edge type to trigger on.
    #   POS_EDGE = 1
    #   NEG_EDGE = 2
    #   BOTH_EDGE = 3
    daq_module.set("edge", 1)
    # Note: We do not manually set level and hysteresis in
    # this example, rather we set the findlevel parameter to 1 and let
    # the Data Acquisition Module determine an appropriate level and hysteresis for us.
    #
    # level (double):
    # The set the trigger level.
    # trigger_level = 0.70
    # daq_module.set('level', trigger_level)
    #
    # hysteresis (double):
    #   The hysterisis is effectively a second criteria (if non-zero) for
    #   triggering and makes triggering more robust in noisy signals. When the
    #   trigger `level` is violated, then the signal must return beneath (for
    #   positive trigger edge) the hysteresis value in order to trigger.
    #
    # The size of the internal buffer used to store data, this should be larger
    # than trigger_duration.
    trigger_duration = 0.010
    # The length of time to record the data for each time we trigger.
    daq_module.set("duration", trigger_duration)
    trigger_delay = -0.25 * trigger_duration
    daq_module.set("delay", trigger_delay)
    # Do not return overlapped trigger events.
    daq_module.set("holdoff/time", trigger_duration)
    daq_module.set("holdoff/count", 0)

    # Unrequired parameters when type is EDGE_TRIGGER:
    # daq_module.set('bitmask', 1)  % For DIGITAL_TRIGGER
    # daq_module.set('bits', 1)  % For DIGITAL_TRIGGER
    # daq_module.set('bandwidth', 10)  % For TRACKING_TRIGGER

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
    daq_module.set("grid/mode", 2)
    # grid/repetitions (int)
    #   The number of times to average.
    daq_module.set("grid/repetitions", 1)
    # grid/cols (int)
    #   Specify the number of columns in the grid's matrix. The data from each
    #     row is interpolated onto a grid with the specified number of columns.
    num_cols = 500
    daq_module.set("grid/cols", num_cols)
    # grid/rows (int)
    #   Specify the number of rows in the grid's matrix. Each row is the data
    #   recorded from one trigger.
    num_rows = 500
    daq_module.set("grid/rows", 500)
    # grid/direction (int)
    #   Specify the ordering of the data stored in the grid's matrix.
    #     0: Forward - the data in each row is ordered chronologically, e.g., the
    #       first data point in each row corresponds to the first timestamp in the
    #       trigger data.
    #     1: Reverse - the data in each row is ordered reverse chronologically,
    #       e.g., the first data point in each row corresponds to the last
    #       timestamp in the trigger data.
    #     2: Bidirectional - the ordering of the data alternates between Forward
    #        and Backward ordering from row-to-row. The first row is Forward ordered.
    daq_module.set("grid/direction", 0)

    # The number of grids to record (if not running in endless mode).
    # In grid mode, we will obtain count grids. The total
    # number of triggers is equal to n = count *
    # grid/rows * grid/repetitions
    daq_module.set("count", num_grids)

    # We will perform intermediate reads from the module. When a grid is
    # complete and read() is called, the data is removed from the module. We
    # have to manage saving of the finished grid ourselves if we perform
    # intermediate reads.
    data = {}
    data[triggerpath] = []

    # Subscribe to the device node paths we would like to record when the trigger criteria is met.
    pid_error_stream_path = "/%s/pids/0/stream/error" % device
    node_paths = daq.listNodes(pid_error_stream_path, 7)
    # If this node is present, then the instrument has the PID Option. In this
    # case additionally subscribe to a PID's error. Note, PID streaming nodes
    # not available on HF2 instruments.
    if pid_error_stream_path.upper() in node_paths:
        daq_module.subscribe(pid_error_stream_path)
        daq.setDouble("/%s/pids/0/stream/rate" % device, 30e3)
        data[pid_error_stream_path] = []
    # Note: We subscribe to the trigger signal path last to ensure that we obtain
    # complete data on the other paths (known limitation). We must subscribe to
    # the trigger signal path.
    daq_module.subscribe(triggerpath)

    if plot:
        fig, axis = plt.subplots()
        # Initialize the image plot with NANs - we'll only update the img's data
        # in the loop.
        img = np.empty(
            (
                num_rows,
                num_cols,
            )
        )
        img[:] = np.nan
        img = axis.imshow(img, cmap="Blues")
        num_ticks = 5
        ticks = np.linspace(0, num_cols, num_ticks)
        ticklabels = [
            f"{trigger_delay + trigger_duration * tick / num_cols:0.3f}"
            for tick in ticks
        ]
        axis.set_xticks(ticks)
        axis.set_xticklabels(ticklabels)
        colorbar = fig.colorbar(img)
        colorbar.formatter.set_useOffset(False)
        colorbar.update_ticks()
        axis.set_title("Demodulator $R$ Data plotted as a Matrix")
        axis.set_xlabel("Time, relative to trigger ($s$)")
        axis.set_ylabel("Grid row index")
        plt.ion()

    # Arm the Data Acquisition Module: ready for trigger acquisition.
    daq_module.execute()
    # Tell the Data Acquisition Module to determine the trigger level.
    daq_module.set("findlevel", 1)
    findlevel = 1
    timeout = 10  # [s]
    t0 = time.time()
    while findlevel == 1:
        time.sleep(0.05)
        findlevel = daq_module.getInt("findlevel")
        if time.time() - t0 > timeout:
            daq_module.finish()
            raise RuntimeError(
                "Data Acquisition Module didn't find trigger level after %.3f seconds."
                % timeout
            )
    level = daq_module.getDouble("level")
    hysteresis = daq_module.getDouble("hysteresis")
    print(
        f"Data Acquisition Module found and set level: {level},",
        f"hysteresis: {hysteresis}.",
    )

    flags = 0
    return_flat_data_dict = True
    num_finished_grids = 0
    timeout = 120  # [s]
    t0 = time.time()
    while not daq_module.finished():
        # Read out the intermediate data captured by the Data Acquisition Module.
        data_read = daq_module.read(return_flat_data_dict)
        if (triggerpath in data_read) and data_read[triggerpath]:
            # Note, if 'count' > 1 then more than one grid could be returned.
            num_grids_read = len(data_read[triggerpath])
            for i in range(num_grids_read):
                flags = data_read[triggerpath][i]["header"]["flags"]
                if flags & 1:
                    # The first bit of flags is set to 1 when the grid is complete and the
                    # configured number of repetitions have completed.
                    num_finished_grids = num_finished_grids + 1
                    print(f"Finished grid {num_finished_grids} of {num_grids}.")
                    data[triggerpath].append(data_read[triggerpath][i])
                    if pid_error_stream_path in data_read:
                        # We only get PID data if the (non-HF2) device has the PID Option.
                        data[pid_error_stream_path].append(
                            data_read[pid_error_stream_path][i]
                        )
            print(
                f"Overall progress: {daq_module.progress()[0]}. \
                     Grid {num_finished_grids} flags: {flags[0]}."
            )
            if plot:
                # Visualize the last grid's demodulator data (the demodulator used as
                # the trigger path) from the intermediate read(). Plot the updated
                # grid.
                img.set_data(data_read[triggerpath][-1]["value"])
                img.autoscale()
        else:
            print("No update available since last read.")
        if plot:
            plt.pause(0.01)
        else:
            time.sleep(0.05)
        if time.time() - t0 > timeout:
            # Leave the loop if we're not obtaining triggers/grids quickly enough.
            if num_finished_grids == 0:
                # If we didn't even get one grid, stop the module, delete its
                # thread and raise an error.
                daq_module.finish()
                raise RuntimeError(
                    f"Failed to record any grids before timeout ({timeout} seconds). "
                )
            print(
                f"Recorded {num_finished_grids} grids. Loop timed-out after {timeout} s "
                f"before acquiring all {num_grids} grids."
            )
            break

    if not flags & 1:
        # The Data Acquisition Module finished recording since performing the previous intermediate
        # read() in the loop: Do another read() to get the final data.
        print(
            "Data Acquisition Module finished since last intermediate read() in loop, \
                reading out finished grid(s)."
        )
        data_read = daq_module.read(return_flat_data_dict)
        num_grids_read = len(data_read[triggerpath])
        for i in range(num_grids_read):
            flags = data_read[triggerpath][i]["header"]["flags"]
            if flags & 1:
                data[triggerpath].append(data_read[triggerpath][i])
                if pid_error_stream_path in data_read:
                    # We only get PID data if the (non-HF2) device has the PID Option.
                    data[pid_error_stream_path].append(
                        data_read[pid_error_stream_path][i]
                    )
            if plot:
                img.set_data(data_read[triggerpath][-1]["value"])
                img.autoscale()
                fig.canvas.draw()

    # Stop the Module (this is also ok if daq_module.finished() is True).
    daq_module.finish()

    if plot:
        plt.ioff()
        print("Please close the figure to exit the example...")
        plt.show()

    assert triggerpath in data, f"Ooops, we didn't get any data for `{triggerpath}`."


if __name__ == "__main__":
    import sys
    from pathlib import Path

    cli_util_path = Path(__file__).resolve().parent / "../../utils/python"
    sys.path.insert(0, str(cli_util_path))
    cli_utils = __import__("cli_utils")
    cli_utils.run_commandline(run_example, __doc__)
    sys.path.remove(str(cli_util_path))
