%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Connect to instrument
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear ziDAQ; close all; clear; clc;

%%% VHFLI, GHFLI, SHFLI, UHFLI
device = 'dev2730';
interface = '1GbE';  % '1GbE or 'USB'
host = '127.0.0.1';
port = 8004;
apilevel = 6;

%%% MFLI, MFIA
% device = 'dev4123';
% interface = 'PCIe';
% host = ['mf-' device];
% port = 8004;
% apilevel = 6;

%%% HF2
% device = 'dev1902';
% interface = 'USB';
% host = '127.0.0.1';
% port = 8005;
% apilevel = 1;

ziDAQ('connect', host, port, apilevel);
ziDAQ('connectDevice', device, interface);

devtype = ziDAQ('getString', ['/' device '/features/devtype']);
fprintf(['The API client is connected to %s of type %s via the ' ...
    'data server with the following version:\n'], upper(device), devtype);
fprintf('Client: %s\n', ziDAQ('version'));
fprintf('Server: %s\n', ziDAQ('getString', '/zi/about/version'));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Adjust device settings
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

data_rate_demod_nominal = 200;

ziDAQ('set', {
    ['/' device '/demods/0/rate'], data_rate_demod_nominal
    ['/' device '/demods/0/enable'], 1
});

data_rate_demod = ziDAQ('getDouble', ['/' device '/demods/0/rate']);
fprintf('Demodulator data rate: %.2f Sa/s\n', data_rate_demod);

clockbase = ziDAQ('getDouble', ['/' device '/clockbase']);
fprintf('Sampling rate of device timestamp: %.1f MSa/s\n', clockbase*1e-6);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Data Streaming module
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

stream = ziDAQ('dataStreamingModule');

demod_path_1 = ['/' device '/demods/0/sample'];

signal_paths = {};
signal_paths{end+1} = [demod_path_1, '.x'];
signal_paths{end+1} = [demod_path_1, '.y'];

for n = 1:length(signal_paths)
    fprintf('Subscribing to %s\n', signal_paths{n});
    ziDAQ('subscribe', stream, signal_paths{n});
end

total_duration_sec = 3.0;  % second
ziDAQ('set', stream, 'duration', total_duration_sec);

timeout_sec = 1.5*total_duration_sec;
start_time = tic;
ziDAQ('execute', stream);
while toc(start_time) < timeout_sec
    fprintf('Progress %0.0f%%\n', ziDAQ('progress', stream) * 100);
    if ziDAQ('finished', stream)
       break;
    end
    pause(1.0);
end

fprintf('Execution is done? %d\n', ziDAQ('finished', stream));
fprintf('Actual duration of acquisition: %0.2f seconds\n', ...
    ziDAQ('getDouble', stream, 'duration'));

data = ziDAQ('read', stream);
fprintf('Acquired data are available for processing.\n')

ziDAQ('unsubscribe', stream, '*');
fprintf('All signal paths are unsubscribed.\n')

ziDAQ('clear', stream);
fprintf('The module object is destroyed.\n')

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Disconnect from instrument
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% ziDAQ('disconnectDevice', device)
clear ziDAQ;
fprintf('Disconnected from the instrument.\n')

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Extract and plot signals
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ts = data.(device).('timestamp');
t = double(ts - ts(1))/clockbase;

signals = rmfield(data.(device), 'timestamp');
paths = fieldnames(signals);

figure('Name','Signals','NumberTitle','on','Position',[500 200 1000 600]);
set(gca,'FontSize',12,'LineWidth',1.0,'Color',[1 1 1],'Box','on');
hold on
cmap = hsv(length(paths));
for n = 1:length(paths)
    h = plot(t,signals.(paths{n}));
    set(h,'LineWidth',1,'LineStyle','-','Color',cmap(n,:))
end
title('Demodulator')
xlabel('Time (s)','fontsize',10,'fontweight','n','color','k');
ylabel('Value (a.u.)','fontsize',10,'fontweight','n','color','k');
legend(paths, 'Interpreter', 'none');
grid on

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
