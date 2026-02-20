%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Connect to instrument
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear ziDAQ; close all; clear; clc;

%%% VHFLI, GHFLI, SHFLI, UHFLI
device = 'dev12027';
interface = '1GbE';  % '1GbE or 'USB'
host = '127.0.0.1';
port = 8004;
apilevel = 6;

%%% MFLI, MFIA
% device = 'dev3337';
% interface = 'PCIe';
% host = ['mf-' device];
% port = 8004;
% apilevel = 6;

%%% HF2
% device = 'dev878';
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

data_rate_demod_nominal = 2000;

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

signal_path = ['/' device '/demods/0/sample.r'];
result_path = 'demods_0_sample_r';
ziDAQ('subscribe', stream, signal_path);
fprintf('Subscribed to the signal path.\n');

ziDAQ('set', stream, 'duration', 0);   % Endless acquisition
timeout_sec = 10;   % second

figure('Name','Demodulation','NumberTitle','on');
set(gca,'FontSize',12,'LineWidth',1.0,'Color',[1 1 1],'Box','on');
hold on
title('Demodulated Signal')
xlabel('Time (s)','fontsize',10,'fontweight','n','color','k');
ylabel('Amplitude (a.u.)','fontsize',10,'fontweight','n','color','k');
xlim([-0.5 timeout_sec + 1.0]);
grid on

ts_init = 0;
start_time = tic;
ziDAQ('execute', stream);
fprintf('Started the acquisition.\n');
while toc(start_time) < timeout_sec
    pause(1.5);
    fprintf('Elapsed time: %0.1f sec.\n', toc(start_time));
    data = ziDAQ('read', stream);
    if ~isempty(data)
        ts = data.(device).('timestamp');
        if ts_init == 0 && ~isempty(ts)
            ts_init = ts(1);
        end
        t = double(ts - ts_init)/clockbase;
        signal = data.(device).(result_path);
        plot(t,signal);
    end
end
ziDAQ('finish', stream);
data = ziDAQ('read', stream);
if ~isempty(data)
    ts = data.(device).('timestamp');
    t = double(ts - ts_init)/clockbase;
    signal = data.(device).(result_path);
    plot(t,signal);
end
fprintf('Finished acquisition in %0.1f sec.\n', toc(start_time));

ziDAQ('clear', stream);
fprintf('Destroyed the module object.\n')

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Disconnect from instrument
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% ziDAQ('disconnectDevice', device)
clear ziDAQ;
fprintf('Disconnected from the instrument.\n')

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
