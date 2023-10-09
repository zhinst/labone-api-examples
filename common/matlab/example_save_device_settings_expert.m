function filename_full_path = example_save_device_settings_expert(device_id, varargin)
% EXAMPLE_SAVE_DEVICE_SETTINGS_EXPERT Save and load device settings to and from file with ziDAQ's deviceSettings module
%
% USAGE example_save_device_settings_expert(device_id)
%
% Demonstrate how to save and load Zurich Instruments device settings
% asynchronously using the ziDeviceSettings class from the device specified by
% DEVICE_ID, e.g., 'dev1000' or 'uhf-dev1000'.
%
% Connect to a Zurich Instruments instrument, save the instrument's settings
% to file, toggle the signal output enable and reload the settings file.
%
% NOTE This example is intended for experienced users who require a
% non-blocking (asynchronous) interface for loading and saving settings. In
% general, the utility functions ziSaveSettings() and ziLoadSettings() are
% more appropriate; see `example_save_device_settings_simple'.
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
apilevel_example = 6;
% Create an API session; connect to the correct Data Server for the device.
[device, props] = ziCreateAPISession(device_id, apilevel_example);
ziApiServerVersionCheck();

% Define parameters relevant to this example. Default values specified by the
% inputParser below are overwritten if specified as name-value pairs via the
% `varargin` input argument.
p = inputParser;
% The xml file (without extension) to save instrument settings to.
default_filename_noext = [datestr(now, 'yyyymmdd_HHMM') '_settings'];
p.addParamValue('filename_noext', default_filename_noext, @isstr);
% The directory to save the settings file. Use current working directory as default.
p.addParamValue('directory', ['.', filesep], @isstr);
p.parse(varargin{:});

% Create a handle to access the deviceSettings thread
h = ziDAQ('deviceSettings');
ziDAQ('set', h, 'device', device);

toggleDeviceSetting(device);

fprintf('Saving settings...\n');
ziDAQ('set', h, 'command', 'save');
ziDAQ('set', h, 'filename', p.Results.filename_noext);
% Set the path to '.' to save to the current directory. Note: this
% example/m-file will have to be executed in a folder where you have write access.
ziDAQ('set', h, 'path', p.Results.directory);

ziDAQ('execute', h);
while ~ziDAQ('finished', h)
  pause(0.2);
end

settings_path = ziDAQ('getString', h, 'path');
filename_full_path = fullfile(settings_path, [p.Results.filename_noext '.xml']);
fprintf('Saved file: ''%s''.\n', filename_full_path);

toggleDeviceSetting(device);

fprintf('Loading settings...\n');
ziDAQ('set', h, 'command', 'load');
ziDAQ('set', h, 'filename', p.Results.filename_noext);

ziDAQ('execute', h);
while ~ziDAQ('finished', h)
  pause(0.2);
end
fprintf('Done.\n');

% Release module resources. Especially important if modules are created
% inside a loop to prevent excessive resource consumption.
ziDAQ('clear', h);
end


function toggleDeviceSetting(device)
path = ['/' device '/sigouts/0/on'];
on = ziDAQ('getInt', path);
if (on)
    on = 0;
else
    on = 1;
end
fprintf('Toggling ''%s''.\n', path);
ziDAQ('setInt', path, on);
ziDAQ('sync');
end
