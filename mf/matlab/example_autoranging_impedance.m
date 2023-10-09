function example_autoranging_impedance(device_id, varargin)
% EXAMPLE_AUTORANGING_IMPEDANCE Demonstrate how to perform a manually triggered
% autoranging for impedance while working in manual range mode.
%
% USAGE EXAMPLE_AUTORANGING_IMPEDANCE(DEVICE_ID)
%
% The example sets the device to impedance manual range mode and executes a
% single auto ranging event.
% DEVICE_ID should be a string, e.g., 'dev1000'.
%
% NOTE Additional configuration: Connect Impedance Testfixture and attach a 1kOhm
% resistor
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
% Copyright 2008-2016 Zurich Instruments AG

clear ziDAQ;

if ~exist('device_id', 'var')
    error(['No value for device_id specified. The first argument to the ' ...
           'example should be the device ID on which to run the example, ' ...
           'e.g. ''dev1000''.'])
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

% This example requires an MF device with IA option.
if ~ismember('IA', props.options)
    installed_options_str = ''; % Note: strjoin() unavailable in Matlab 2009.
    for option=props.options
      installed_options_str = [installed_options_str, ' ', option{1}];
    end
    error(['Required option set not satisfied. This example requires an MF ' ...
           'Instrument with the IA Option installed. Device `%s` reports ' ...
           'devtype `%s` and options `%s`.'], ...
          device, props.devicetype, installed_options_str);
end

% Create a base configuration: Disable all available outputs, awgs,
% demods, scopes,...
ziDisableEverything(device);

imp_c = '0';
curr_c = mat2str(ziDAQ('getInt', ['/' device '/imps/' imp_c  '/current/inputselect']));
volt_c = mat2str(ziDAQ('getInt', ['/' device '/imps/' imp_c  '/voltage/inputselect']));
man_curr_range = 10e-3;
man_volt_range = 10e-3;

%% Configure the device ready for this experiment.
% The following channels and indices work on all devices with IA option. The
% values below may be changed if the instrument has multiple IA modules.
ziDAQ('setInt', ['/' device '/imps/' imp_c '/enable'], 1);
ziDAQ('setInt', ['/' device '/imps/' imp_c '/mode'], 0);
ziDAQ('setInt', ['/' device '/imps/' imp_c '/auto/output'], 1);
ziDAQ('setInt', ['/' device '/imps/' imp_c '/auto/bw'], 1);
ziDAQ('setDouble', ['/' device '/imps/' imp_c '/freq'], 500);
ziDAQ('setInt', ['/' device '/imps/' imp_c '/auto/inputrange'], 0);
ziDAQ('setDouble', ['/' device '/currins/' curr_c '/range'], man_curr_range);
ziDAQ('setDouble', ['/' device '/sigins/' volt_c '/range'], man_volt_range);
ziDAQ('sync');

%% Trigger an autoranging
% Afater setting the device in impedance manual mode we trigger a single auto
% ranging event and wait until it is finished
fprintf('Start auto ranging. This might take a few seconds.\n');
ziDAQ('setInt', ['/' device '/currins/' curr_c '/autorange'], 1);
ziDAQ('setInt', ['/' device '/sigins/' volt_c '/autorange'], 1);
ziDAQ('sync');
currins_autorange = 1;
sigins_autorange = 1;
timeout = 20;
t0 = tic;
while currins_autorange || sigins_autorange
   if toc(t0) > timeout
       error('Autoranging failed to completed after %.2f s.\n', timeout);
   end
   pause(0.2);
   currins_autorange = ziDAQ('getInt', ['/' device '/currins/' curr_c '/autorange']);
   sigins_autorange = ziDAQ('getInt', ['/' device '/sigins/' volt_c '/autorange']);
end

fprintf('Auto ranging finished after %.1f s.\n', toc(t0));
auto_curr_range = ziDAQ('getDouble', ['/' device '/currins/' curr_c '/range']);
auto_volt_range = ziDAQ('getDouble', ['/' device '/sigins/' volt_c '/range']);
fprintf('Current range changed from %0.1eA to %0.1eA.\n', man_curr_range, auto_curr_range);
fprintf('Voltage range changed from %0.1eV to %0.1eV.\n', man_volt_range, auto_volt_range);
