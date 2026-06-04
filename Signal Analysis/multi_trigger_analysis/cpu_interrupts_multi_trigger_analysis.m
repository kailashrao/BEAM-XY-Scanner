% cpu_interrupts_multi_trigger_analysis.m (test.m)
% Updated 6/4/2026 by Kailash Rao

% Works for T0002-T0005 (CPU Interrupts)

% CPU Interrupts take significant time to execute compared to the oscilloscope's current resolution of 1.6us
% Since delay is significant, we define the Pico's high voltage threshold (PHVT) to be fixed (2.1V)

% Strategy: look forward and backward from the trigger 
% to find when encoder signal crossed PHVT and finished rising
% total delay = rise time to PHVT (10% to PHVT) + Pico interrupt processing time (PHVT to Trigger)

%% Multi-Trigger Coherent Latency & Statistics Analyzer
clear; clc; close all;

% --- Configuration ---
[fileName, pathName] = uigetfile('data/*.CSV', 'Select a Data Set');
csvFileName = fullfile(pathName, fileName);  % Target dataset for this run
lookback_samples = 250;        % Causal window size to find the encoder edge
lookforward_samples = 50;      % NEW: Lookahead window to let the encoder finish rising
v_pico_high_threshold = 2.1;   % RP2040 Input Logic-High Threshold (Volts)

% --- Setup Import Settings to Bypass Tektronix Metadata ---
opts = delimitedTextImportOptions("NumVariables", 5);
opts.DataLines = [17, Inf]; 
opts.Delimiter = ",";
opts.VariableNames = ["Time", "CH1", "CH1_Peak", "CH2", "CH2_Peak"];
opts.VariableTypes = ["double", "double", "double", "double", "double"];

fprintf('Importing continuous time-series data from: %s\n', csvFileName);
data = readtable(csvFileName, opts);
time = data.Time;
ch1_input = data.CH1;    % Encoder Channel A
ch2_trigger = data.CH2;  % Pico Trigger Output
dt = mean(diff(time));

%% 1. Vectorized Rising-Edge Detection for ALL Channel 2 Triggers
ch2_low = min(ch2_trigger);
ch2_high = max(ch2_trigger);
ch2_mid = ch2_low + 0.50 * (ch2_high - ch2_low);

% Identify all indices where Channel 2 crosses the 50% threshold on a rising edge
all_trigger_indices = find(ch2_trigger(2:end) >= ch2_mid & ch2_trigger(1:end-1) < ch2_mid) + 1;
num_triggers = length(all_trigger_indices);

fprintf('Detected %d distinct radar trigger pulses in dataset.\n', num_triggers);

if num_triggers == 0
    error('No radar triggers detected. Verify Channel 2 voltage thresholds.');
end

%% 2. Loop Through Every Trigger Pulse to Process Latencies
% Pre-allocate arrays for table construction
trigger_number = (1:num_triggers)';
rc_time_constants_us = zeros(num_triggers, 1);
time_to_pico_high_us = zeros(num_triggers, 1); 
pico_delays_us = zeros(num_triggers, 1);
total_delays_us = zeros(num_triggers, 1);

for i = 1:num_triggers
    idx_trigger = all_trigger_indices(i);
    t_trigger_rise = time(idx_trigger);
    
    % Define the localized search window extending slightly past the trigger
    idx_search_start = max(1, idx_trigger - lookback_samples);
    idx_search_end = min(length(time), idx_trigger + lookforward_samples);
    search_window_ch1 = ch1_input(idx_search_start:idx_search_end);
    search_window_time = time(idx_search_start:idx_search_end);
    
    % Find the relative index of the trigger within this new window
    idx_trigger_rel = idx_trigger - idx_search_start + 1;
    
    % Find where the encoder last sat below 2.1V before the trigger registered
    idx_local_pico_high = find(search_window_ch1(1:idx_trigger_rel) < v_pico_high_threshold, 1, 'last') + 1;
    t_pico_registered_high = search_window_time(idx_local_pico_high);
    
    % Establish local 10% and 90% threshold baselines for RC calculations
    ch1_high_local = max(search_window_ch1);
    ch1_low_local = min(search_window_ch1);
    v_rise_10 = ch1_low_local + 0.10 * (ch1_high_local - ch1_low_local);
    v_rise_90 = ch1_low_local + 0.90 * (ch1_high_local - ch1_low_local);
    
    % Pinpoint 10% edge crossing point (must occur before the trigger)
    idx_local_rise_start = find(search_window_ch1(1:idx_trigger_rel) < v_rise_10, 1, 'last') + 1;
    t_encoder_rise_start = search_window_time(idx_local_rise_start);
    
    % FIX: Pinpoint 90% edge crossing point by searching FORWARD from the 10% start point
    idx_relative_rise_end = find(search_window_ch1(idx_local_rise_start:end) >= v_rise_90, 1, 'first');
    if isempty(idx_relative_rise_end)
        idx_local_rise_end = length(search_window_ch1); % Fallback to window boundary
    else
        idx_local_rise_end = idx_local_rise_start + idx_relative_rise_end - 1;
    end
    t_encoder_rise_end = search_window_time(idx_local_rise_end);
    
    % Compute Metrics and Convert directly to Microseconds (us)
    rc_time_constants_us(i) = (t_encoder_rise_end - t_encoder_rise_start) * 1e6;
    time_to_pico_high_us(i) = (t_pico_registered_high - t_encoder_rise_start) * 1e6; 
    pico_delays_us(i)       = (t_trigger_rise - t_pico_registered_high) * 1e6;
    total_delays_us(i)      = (t_trigger_rise - t_encoder_rise_start) * 1e6;
end

%% 3. Generate and Display the Trial Summary Table
TrialTable = table(trigger_number, rc_time_constants_us, time_to_pico_high_us, pico_delays_us, total_delays_us, ...
    'VariableNames', {'Pulse_ID', 'RC_Rise_Time_us', 'Time_To_Pico_High_us', 'Pico_Delay_us', 'Total_Delay_us'});

fprintf('\n======================= DATASET SUMMARY TABLE =======================\n');
disp(TrialTable);

%% 4. Compute and Aggregate Core Statistical Metrics
stats_labels = {'Mean'; 'Median'; 'Max'; 'Min'; 'StdDev'};
stats_rc     = [mean(rc_time_constants_us); median(rc_time_constants_us); max(rc_time_constants_us); min(rc_time_constants_us); std(rc_time_constants_us)];
stats_t2high = [mean(time_to_pico_high_us); median(time_to_pico_high_us); max(time_to_pico_high_us); min(time_to_pico_high_us); std(time_to_pico_high_us)]; 
stats_pico   = [mean(pico_delays_us); median(pico_delays_us); max(pico_delays_us); min(pico_delays_us); std(pico_delays_us)];
stats_total  = [mean(total_delays_us); median(total_delays_us); max(total_delays_us); min(total_delays_us); std(total_delays_us)];

StatsTable = table(stats_labels, stats_rc, stats_t2high, stats_pico, stats_total, ...
    'VariableNames', {'Metric', 'RC_Rise_Time_us', 'Time_To_Pico_High_us', 'Pico_Delay_us', 'Total_Delay_us'});

fprintf('======================= AGGREGATED STATISTICS =======================\n');
disp(StatsTable);

%% 5. Optional: Plot Jitter Distribution Profile
figure('Name', 'Radar Trigger Jitter Analysis', 'Color', 'w');
histogram(total_delays_us, 10, 'FaceColor', 'r', 'EdgeColor', 'w');
grid on;
xlabel('Total Alignment Latency (\mu s)');
ylabel('Occurrences / Pulses');
title(sprintf('Coherent Trigger Jitter Distribution Profile (N = %d)', num_triggers));