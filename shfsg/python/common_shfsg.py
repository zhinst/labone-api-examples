""" Helper functions for SHFSG examples.
"""
import time


def load_sequencer_program(daq, device_id, seq_id, sequencer_program):
    """Compiles and upload a given sequencer program.

    Arguments:
      daq: Data Server instance
      device_id: Device ID
      seq_id: sequencer ID
      sequencer_program: sequencer program to be uploaded

    """
    # Disable AWG, in case it's running from a previous run:
    num_chan = int(daq.getString(f"/{device_id}/FEATURES/DEVTYPE")[-1])
    for i in range(num_chan):
        daq.setInt(f"/{device_id}/SGCHANNELS/{i}/AWG/ENABLE", 0)

    # Upload to AWG
    awgModule = daq.awgModule()
    awgModule.set("device", device_id)
    awgModule.set("index", seq_id)
    awgModule.execute()

    awgModule.set("compiler/sourcestring", sequencer_program)
    timeout = 10
    t_start = time.time()
    while awgModule.getInt("compiler/status") == -1:
        time.sleep(0.1)
        if time.time() - t_start > timeout:
            statusstring = awgModule.getString("compiler/statusstring")
            raise AssertionError(
                f"Failed to compile program after {timeout} s. "
                f"compiler/statusstring: `{statusstring}`"
            )
    # Check status = 0, compiler emitted no warnings
    status = awgModule.getInt("compiler/status")
    statusstring = awgModule.getString("compiler/statusstring")
    assert (
        status == 0
    ), f"Compiler status is {status}. compiler/statusstring reports: {statusstring}"

    # wait for upload to finish
    timeout = 10
    t_start = time.time()
    while awgModule.getDouble("progress") < 1.0 and awgModule.getInt("elf/status") != 1:
        time.sleep(0.5)
        if time.time() - t_start > timeout:
            statusstring = awgModule.getString("compiler/statusstring")
            raise AssertionError(
                f"Failed upload program after {timeout} s. statustring: {statusstring}"
            )
    status = awgModule.getInt("elf/status")
    statusstring = awgModule.getString("compiler/statusstring")
    assert status == 0, f"Failed to upload program. statustring: {statusstring}"

    daq.sync()
