function data = hf2_example_zsync_poll()
% HF2_EXAMPLE_ZYSNC_POLL Poll data from two HF2s with synchronised timestamps
%
% USAGE sample = HF2_EXAMPLE_ZSYNC_POLL()
%
% Synchronise the timestamps from two HF2s using the HF2's ZSync
% capability combined with the Multi-Device Module and poll data from
% both devices using ziDAQServer's poll method.
%
% NOTE This example can only run on HF2 Series instruments and requires two
% HF2s connected to the same PC via USB. This example assumes that the HF2
% with the lowest serial number is the leader and the HF2 with the next serial
% number is the follower. The serial number is the number contained in the
% device's ID, e.g., 'dev1000'.  In order to correctly use the ZSync
% functionality, these HF2s must be configured and power-cycled as following:
%
%   1. Power-off both follower and leader. Connect zsync cables between follower and
%   leader. Attach both HF2s to host PC via USB.
%
%   2. Power-on the leader device, wait until the LEDs stop blinking red on
%   the front-panel.
%
%   3. Power-on the follower device, wait until the LEDs stop blinking red on the
%   front-panel.
%
% If the above fails, please restart the HF2's Data Server program `ziServer`
% and start again.
%
% NOTE Please ensure that the ziDAQ folders 'Driver' and 'Utils' are in your
% Matlab path. To do this (temporarily) for one Matlab session please navigate
% to the ziDAQ base folder containing the 'Driver', 'Examples' and 'Utils'
% subfolders and run the Matlab function ziAddPath().
% >>> ziAddPath;
%
% Use either of the commands:
% >>> help ziDAQ
% >>> doc ziDAQ
% in the Matlab command window to obtain help on all available ziDAQ commands.
%
% Copyright 2008-2018 Zurich Instruments AG

clear ziDAQ;

% Check ziDAQ's ziDevices (in the Utils/ subfolder) is in the path
% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end

% Create a connection to the HF2 Data Server for the HF2
port = 8005;
% The API level supported by this example.
apilevel_example = 1;
ziDAQ('connect', 'localhost', port, apilevel_example);
ziApiServerVersionCheck();

server_version = ziDAQ('getInt', '/zi/about/revision');
if server_version < 28460
  fprintf('ZSync requires at least HF2 Data Server (ziServer.exe) version r28460.\n')
  fprintf('Please update your LabOne installation, LabOne 15.01 or newer is required.\n')
  return
end

% Get the device's names (e.g. 'dev1000')
devices = ziDevices();
if length(devices) ~= 2
  fprintf('Detected %d devices, this example requires 2 HF2 devices connected to the same host PC.\n', length(devices));
  return
end
if str2num(devices{1}(4:end)) < str2num(devices{2}(4:end))
  device_leader = devices{1};
  device_follower = devices{2};
else
  device_follower = devices{1};
  device_leader = devices{2};
end

fprintf('Will run the example using leader device ''%s'' and follower device ''%s''.\n', device_leader, device_follower)

demod_rate = 2e3;

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device{1});
ziDisableEverything(device{2});

% use the multidevicesync modul to synchronzie the devices. This must only
% be performed once and is valid until the devices are power-cycled. Note,
% that before performing this configuration via API, the devices must be
% attached and power-cycled as following:
% 1. Power-off both follower and leader. Connect zsync cables between leader
% ('ZSync Out') and leader ('ZSync In'). Attach both HF2s to host PC via USB.
% 2. Power-on the leader device, wait until the LEDs stop blinking red on
% the front-panel.
% 3. Power-on the follower device, wait until the LEDs stop blinking red on
% the front-panel.
h = ziDAQ('multiDeviceSyncModule');
ziDAQ('set', h, 'group', 0);
ziDAQ('execute', h);
ziDAQ('set', h, 'devices', [device_leader ',' device_follower]);
ziDAQ('set', h, 'start', 1);
disp(ziDAQ('getString', h, 'message'))

while 1
  status = ziDAQ('getInt', h, 'status');
  disp(ziDAQ('getString', h, 'message'))
  if (status == 2)
    break;
  end
  if (status == -1)
    ziDAQ('clear', h);
    error('Device Synchronization failed.')
  end
  pause(0.2)
end

% We will only plot data from the HF2s' Digital I/O (DIO) and as such do not
% need to configure the devices' HF inputs and outputs. The DIO data is
% delivered as the 'bits' field in demodulator samples; configure the
% demodulators to obtain demod data from the devices.
for device = {device_follower, device_leader}
  ziDAQ('setDouble', ['/' device{1} '/demods/0/rate'], demod_rate);
  ziDAQ('setDouble', ['/' device{1} '/demods/0/enable'], 1);
  % Enable the DIO
  ziDAQ('setInt', ['/' device{1} '/dios/0/drive'], 1)
end
% Set values of the DIO
ziDAQ('setInt', ['/' device_leader '/dios/0/output'], 1)
ziDAQ('setInt', ['/' device_follower '/dios/0/output'], 0)

% Unsubscribe all streaming data
ziDAQ('unsubscribe', '*');

% Perform a global synchronisation between the device and the data server:
% Ensure that the settings have taken effect on the device before issuing the
% ``poll`` command and clear the API's data buffers to remove any old data.
ziDAQ('sync');

% Subscribe to the devices' demodulators
ziDAQ('subscribe', ['/' device_leader '/demods/0/sample']);
ziDAQ('subscribe', ['/' device_follower '/demods/0/sample']);

% Poll command configuration
poll_length = 0.1; % [s]
poll_timeout = 100; % [ms]
poll_flag = 0; % set to 0: disable the dataloss indicator (or data imbetween
% the polls will be filled with NaNs)

%% Poll for data, it will return as much data as it can since the ``poll`` or ``sync``
data = ziDAQ('poll', poll_length, poll_timeout, poll_flag);

clockbase = double(ziDAQ('getInt', ['/' device_leader '/clockbase']));

% Convert to double, timestamps and sample.bits is uint32.
timestamp_leader = data.(device_leader).demods(1).sample.timestamp;
timestamp_follower = data.(device_follower).demods(1).sample.timestamp;

% stop timesync
ziDAQ('set', h, 'start', 0);

% Poll will not necessarily return aligned demodulator data (by timestamp)
% when subscribed to multiple demodulators (even for the same device). Find
% the first timestamp where we have data from both devices; only plot the data
% where it is available for both devices.
% NOTE If continually polling data via multiple calls to poll, it'd be more
% relevant to align the data between the individual poll commands; not to
% trim the data.
if timestamp_leader(1) <= timestamp_follower(1)
  idx_start_follower = 1;
  idx_start_leader = find(timestamp_leader == timestamp_follower(1), 1, 'first');
else
  idx_start_follower = find(timestamp_follower == timestamp_leader(1), 1, 'first');
  idx_start_leader = 1;
end

if timestamp_leader(end) > timestamp_follower(end)
  idx_end_follower = length(timestamp_follower);
  idx_end_leader = find(timestamp_leader == timestamp_follower(end), '1', 'last');
else
  idx_end_follower = find(timestamp_follower == timestamp_leader(end), '1', 'last');
  idx_end_leader = length(timestamp_leader);
end

if isempty(idx_start_follower) || isempty(idx_start_leader) || isempty(idx_end_follower) || isempty(idx_end_leader)
  ziDAQ('clear', h);
  error('Failed to find matching timestamps in data. Misconfiguration or zysncing failed.')
end

t_leader = double(timestamp_leader)/clockbase;
t_follower = double(timestamp_follower)/clockbase;

figure(1); clf;
hold on; box on; grid on;
% We only plot the first bit of the DIO
plot(t_leader(idx_start_leader:idx_end_leader), double(bitand(1, data.(device_leader).demods(1).sample.bits(idx_start_leader:idx_end_leader))), 'r-x');
plot(t_follower(idx_start_follower:idx_end_follower), double(bitand(1, data.(device_follower).demods(1).sample.bits(idx_start_follower:idx_end_follower))), 'b-o');
ylim([-1, 2]);
legend('0th bit, DIO Leader', '0th bit, DIO Follower');

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);

end
