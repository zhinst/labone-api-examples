%% Description -----------------------------------------------------------
%%% Copyright 2026 Zurich Instruments AG
%%% This example demonstrates how to use the Timeline module in the Zurich Instruments LabOne API for Python.
%%% This example requires the GHFLI instrument and its AWG option to be installed on the device.
%%% A loopback BNC cable is required between Signal Output 1 +V and Signal Input 1 +V of the device.
%%% LabOne version >= 26.07
%%% See the LabOne API User Manual to learn how to obtain the JSON string from the LabOne User Interface:
%%% https://docs.zhinst.com/labone_api_user_manual/modules/timeline

%%% Clear and close everything
close all; clear; clc;
clear ziDAQ;

%% Connect to instrument and apply the required settings -----------------

%%% Define the device ID, interface, and data server host
device = 'dev13016';
device_interface = '1GbE';  % '1GbE' or 'USB'
dataserver_host = 'localhost';

%%% Establish connection to the data server and the instrument
ziDAQ('connect', dataserver_host, 8004, 6);
ziDAQ('connectDevice', device, device_interface);
device_type = ziDAQ('getString', ['/' device '/features/devtype']);
fprintf('Established connection to device %s of type %s.\n', upper(device), device_type);
fprintf('Client version: %s\n', ziDAQ('version'));
fprintf('Server version: %s\n', ziDAQ('getString', '/zi/about/version'));
device_options = ziDAQ('getString', ['/' device '/features/options']);
if ~contains(device_options, 'AWG')
    fprintf('This example requires the AWG option, but it is not installed on device %s of type %s.\n', upper(device), device_type);
    clear ziDAQ
    fprintf('Disconnected the API session.\n')
    return;
end

%%% Configure the instrument for the Timeline experiment
device_settings = {
    ['/' device '/oscs/0/freq'], 200e6
    ['/' device '/sigouts/0/generators/*/enable'], 0
    ['/' device '/generators/3/oscselect'], 0
    ['/' device '/sigouts/0/range'], 0.5
    ['/' device '/sigouts/0/on'], 1
    ['/' device '/sigins/0/range'], 0.5
    ['/' device '/sigins/0/imp50'], 1
    ['/' device '/sigins/0/on'], 1
    ['/' device '/demods/0/adcselect'], 0
    ['/' device '/demods/0/oscselect'], 0
    ['/' device '/demods/0/phaseshift'], 90
    ['/' device '/demods/0/bypass'], 1
};
ziDAQ('set', device_settings);

%%% Time difference in seconds between two consecutive timestamp ticks
dt = ziDAQ('getDouble', ['/' device '/system/properties/timebase']);

%% Carry out measurement with the Timeline module ------------------------

%%% Create a Timeline module instance
tlm = ziDAQ('timelineModule');
ziDAQ('set', tlm, 'device', device);

%%% Enable pulse modulation in the Signal Output port
ziDAQ('set', tlm, 'sigouts/0/modulation/type', 'complex');

%%% Define the JSON string. To obtain it from the LabOne User Interface, 
%%% check out the LabOne API User Manual
json_string = '{"meta":{"schemaVersion":"1.0.0"},"block":{"type":"block","iterations":1,"sequence":[{"type":"section","minDuration":0E0,"signals":{"sigout0":[{"type":"delay","duration":6.4E-8},{"type":"pulse","waveform":"gauss","amplitude":4E-1,"peak":5E-1,"width":1.25E-1,"duration":4.0E-7},{"type":"delay","duration":9.6E-8},{"type":"pulse","waveform":"drag","amplitude":4E-1,"peak":5E-1,"width":1.25E-1,"duration":3.04E-7},{"type":"delay","duration":2.08E-7}],"demod0":[{"type":"delay","duration":3.04E-7},{"type":"measurement","rate":5E7,"duration":1.04E-6}]}}]}}';
try 
    jason_pretty = jsonencode(jsondecode(json_string), 'PrettyPrint', true);
    fprintf('Printing the JSON string...\n');
    disp(jason_pretty);
catch
end 

%%% Apply the JSON string to the Timeline module to define the experiment sequence
ziDAQ('set', tlm, 'sequence/sourcestring', json_string);

%%% Subscribe to the relevant signal paths for data acquisition
signal_paths = {};
demod_path = ['/' device '/demods/0/sample'];
signal_paths{end+1} = [demod_path, '.x'];
signal_paths{end+1} = [demod_path, '.y'];
signal_paths{end+1} = [demod_path, '.r'];
for n = 1:length(signal_paths)
    ziDAQ('subscribe', tlm, signal_paths{n});
end

%%% Execute the Timeline sequence and monitor its progress
fprintf('Starting Timeline execution...\n');
ziDAQ('execute', tlm);
timeout_sec = 5;
t0 = tic;
while ~ziDAQ('finished', tlm)
    if toc(t0) > timeout_sec
        fprintf('Timeout occurred.\n');
        ziDAQ('finish', tlm);
        break;
    end
    pause(0.3);
    fprintf('Progress %0.0f%%\n', ziDAQ('progress', tlm)*100);
end
fprintf('Timeline execution finished with %0.0f%% progress.\n', ziDAQ('progress', tlm)*100);

%%% Read the acquired data and unsubscribe from the signal paths
data = ziDAQ('read', tlm);
ziDAQ('unsubscribe', tlm, '*');

%%% Tear down the Timeline module and close the API session
ziDAQ('clear', tlm);
clear ziDAQ;
fprintf('Disconnected the API session.\n');

%% Post-process the acquired data and plot the results -------------------

%%% Check if the signals exist in the acquired data
if isempty(data) || ...
   ~isfield(data, device) || ...
   ~isfield(data.(device), 'demods') || ...
   isempty(fieldnames(data.(device).demods))

    fprintf('No data acquired.\n');
    return;
end
paths = fieldnames(data.(device).demods);

%%% Extract the timestamp and calculate the relative time
ts = data.(device).demods.(paths{1}){1,1}.timestamp;
t = double(ts - ts(1))*dt;

%%% Plot the demodulated signals 
figure('Name','Signals','NumberTitle','on');
set(gca,'FontSize',12,'LineWidth',1.0,'Color',[1 1 1],'Box','on');
hold on
cmap = hsv(length(paths));
for n = 1:length(paths)
    h = plot(t*1e6, data.(device).demods.(paths{n}){1,1}.value*1e3);
    set(h,'LineWidth',1,'LineStyle','-','Color',cmap(n,:))
end
title('Timeline Module Measurement Results')
xlabel('time (\mus)','fontsize',12,'fontweight','n','color','k');
ylabel('amplitude (mV)','fontsize',12,'fontweight','n','color','k');
legend(paths, 'Interpreter', 'none');
grid on
fprintf('Displayed the results in the plot.\n')
% ------------------------------------------------------------------------
