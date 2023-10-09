function r = example_connect(device_id)
% EXAMPLE_CONNECT A simple example demonstrating how to connect to a Zurich Instruments device
%
% USAGE R = EXAMPLE_CONNECT(DEVICE_ID)
%
% Connect to the Zurich Instruments device specified by DEVICE_ID, obtain a
% single demodulator sample and calculate its RMS amplitude R. DEVICE_ID
% should be a string, e.g., 'dev1000' or 'uhf-dev1000'.
%
% NOTE This is intended to be a simple example demonstrating how to connect
% to a Zurich Instruments device from ziPython. In most cases, data acquistion
% should use either ziDAQServer's poll() method or an instance of the
% ziDAQRecorder class.
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
% See also EXAMPLE_CONNECT_CONFIG, EXAMPLE_POLL.
%
% Copyright 2008-2018 Zurich Instruments AG

clear ziDAQ;

if ~exist('device_id', 'var')
    error(['No value for device_id specified. The first argument to the ' ...
           'example should be the device ID on which to run the example, ' ...
           'e.g. ''dev1000'' or ''uhf-dev1000''.'])
end

% Check the ziDAQ MEX (DLL) and Utility functions can be found in Matlab's path.
if ~(exist('ziDAQ') == 3) && ~(exist('ziCreateAPISession', 'file') == 2)
    fprintf('Failed to either find the ziDAQ mex file or ziDevices() utility.\n')
    fprintf('Please configure your path using the ziDAQ function ziAddPath().\n')
    fprintf('This can be found in the API subfolder of your LabOne installation.\n');
    fprintf('On Windows this is typically:\n');
    fprintf('C:\\Program Files\\Zurich Instruments\\LabOne\\API\\MATLAB2012\\\n');
    return
end

% The API level supported by this example.
supported_apilevel = 6;
% Create an API session; connect to the correct Data Server for the device.
[device, ~] = ziCreateAPISession(device_id, supported_apilevel);
ziApiServerVersionCheck();

branches = ziDAQ('listNodes', ['/' device ], 0);
% Only configure if we have lock-in functionality available.
if any(strcmpi([branches], 'DEMODS'))
  % Enable the demodulator and set a reasonable rate, otherwise the getSample
  % command below will timeout as it won't receive any demodulator data.
  ziDAQ('setInt', ['/' device '/demods/0/enable'], 1);
  ziDAQ('setDouble', ['/' device '/demods/0/rate'], 1.0e3);

  % Perform a global synchronisation between the device and the data server:
  % Ensure that the settings have taken effect on the device before issuing the
  % `getSample` command. Note: `sync` must be issued after waiting for the
  % demodulator filter to settle above.
  ziDAQ('sync');

  % Get a single demodulator sample. Note, `poll` or other higher-level
  % functionality should almost always be be used instead of `getSample`.
  sample = ziDAQ('getSample', ['/' device '/demods/0/sample']);
  r = abs(sample.x + j*sample.y);
  fprintf('Measured RMS amplitude: %eV.\n', r);
else
  r = nan;
end

end
