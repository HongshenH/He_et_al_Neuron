clc;
clear;

dsp_delay = 984;
s_fname_suff_slp = '_slp_fine.mat';

s_fname_sites = 'sites.txt';
s_fname_csv = 'CA2Cre_DREADD_8TT_sbCNO_CNO_sA_CNO.csv';
dset_list = LoadTargets('trials_sbCNO_CNO_sA_CNO_fine.txt');

coef_pix2cm = 3.84615;
% 2 spikes within 10 ms considered as a burst on a single cell basis.
BURST_P = struct();
BURST_P.N = 2;
BURST_P.ISI_N = 0.01;

lcnt = 1;
list_out = cell(1,1);

for did = 1:numel(dset_list)
   
   C = textscan(dset_list{did},'%s %s','Delimiter','\t');
   dset_list{did} = C{1}{1};
   s_trial_fine   = C{2}{1};
   fprintf('Process dataset: %s\n', dset_list{did});
   
   [s, s_trial] = fileparts(dset_list{did});
   [s, s_dataset] = fileparts(s);
   [s, s_mouse] = fileparts(s);
   [s, s_group] = fileparts(s);
   clearvars s;
   
   ntt_file_list = LoadTargetFlist(dset_list{did},'*_TT?.NTT');
   NVT_file_list = LoadTargetFlist(dset_list{did},'*.nvt');
   %
   POS_TS_USEC = NlxNvtLoadYflip(NVT_file_list{1}, coef_pix2cm);
   TS_TRIAL = [POS_TS_USEC(1), POS_TS_USEC(end)];
   
   for fid = 1:numel(ntt_file_list)
      fprintf('\tProcess file: %s\n', ntt_file_list{fid});
      
      s_site = GetSite(fullfile(s_group,s_mouse,s_fname_sites), strcat('CSC',ntt_file_list{fid}(end-4),'.ncs'));
      if isempty(s_site)
         error('unable to extract site name');
      end
      
      % Load spike data from every ntt file. Same code will work for *.nse files too.
      % It is assumed that the input file contain data recorded from only single
      % trial (run1 or run2 etc.) and spikes are already sorted.
      [all_ts, all_cids, all_wfs, all_fets] = NlxGetSpikesAll( ntt_file_list{fid} );
      all_ts = all_ts - dsp_delay;
      
      % Split spike features by cell
      cell_fet = SpkSelectFet(all_fets, all_cids, false);
      
      % Split all spike timestamps by cell
      [cell_ts, cell_ids] = SpkSelectTs(all_ts, all_cids, false);
      
      % Split all spike waveforms by cell
      cell_wfs = SpkSelectWf(all_wfs, all_cids, false);
      %
      bad_cells = false(length(cell_ids),1);
      for ii = 1:length(cell_ids)
         if numel(cell_ts{ii}) < 50
            bad_cells(ii) = true;
         end
      end
      cell_fet(bad_cells) = [];
      cell_ids(bad_cells) = [];
      cell_ts(bad_cells)  = [];
      cell_wfs(bad_cells) = [];
      %
      if numel(cell_ids) == 1 && cell_ids{1} == 0
         error('unsorted file');
         % fprintf('*** SKIP FILE ***\n');
         % continue;
      end
      %
      % Calculate waveform properties
      WFP = SpkWFormProp2(cell_ids, cell_wfs, 1, true);
      WFP_BEST_CH = [WFP(1).best_ch; vertcat(WFP.best_ch)];
      
      % Calculate spike train properties
      STP = SpkTrainProp2(cell_ids, cell_ts, cell_wfs, cell_fet, WFP_BEST_CH, TS_TRIAL, 1);
      
      % remove cluster zero before place field calculation
      cell_fet = cell_fet(2:end);
      cell_ids = cell_ids(2:end);
      cell_ts  = cell_ts(2:end);
      cell_wfs = cell_wfs(2:end);
      
      % Cell types
      CT  = CalcCellTypeWeak( WFP, STP );
      
      % Bursting properties on a per-cell basis
      BURST = SpkBurstPerCell(BURST_P, cell_ts, TS_TRIAL);
      

      for cid = 1:length(STP)
         fprintf('\tProcess cell: %i\n', cell_ids{cid});
         
         %
         s_out = sprintf('%s,%s,%s,%s,%s,%s,%s,%s,', s_group, s_dataset, s_trial, s_trial_fine, ...
            ntt_file_list{fid}, num2str(cell_ids{cid}), ...
            s_mouse, s_site );
         s_out = sprintf('%s%s,', s_out, CT{cid} ); % CELL TYPE
         
         % GCID
         [~, s_tt] = fileparts(ntt_file_list{fid});
         s_gcid = strcat(s_mouse(5:end),s_dataset(4:5),num2str(100*str2num(s_tt(end))+cell_ids{cid}));
         s_out = sprintf('%s%s,', s_out, s_gcid );
         
         % WFP...
         s_out = sprintf('%s%.3f,', s_out, WFP(cid).wf_bad_prop);
         s_out = sprintf('%s%.3f,', s_out, WFP(cid).wf_peak);
         s_out = sprintf('%s%.3f,', s_out, WFP(cid).wf_swing);
         s_out = sprintf('%s%.3f,', s_out, WFP(cid).wf_width);
         s_out = sprintf('%s%.3f,', s_out, WFP(cid).wf_amp_ass);
         s_out = sprintf('%s%.3f,', s_out, WFP(cid).rms);
         
         % STP...
         s_out = sprintf('%s%i,', s_out, STP(cid).num_spk); % whole train!
         s_out = sprintf('%s%.4f,', s_out, STP(cid).frate_peak);
         s_out = sprintf('%s%.4f,', s_out, STP(cid).frate_mean);
         s_out = sprintf('%s%.4f,', s_out, STP(cid).perc_isi_u2ms);
         s_out = sprintf('%s%.4f,', s_out, STP(cid).csi_swing);
         s_out = sprintf('%s%.4f,', s_out, STP(cid).csi_peaks);
         s_out = sprintf('%s%.6f,', s_out, STP(cid).lratio);
         s_out = sprintf('%s%.4f,', s_out, STP(cid).isold);
         
         % BURST
         s_out = sprintf('%s%.4f,', s_out, BURST(cid).num_total);
         s_out = sprintf('%s%.4f,', s_out, BURST(cid).num_per_min);
         s_out = sprintf('%s%.4f,', s_out, BURST(cid).mean_ibi_sec);
         s_out = sprintf('%s%.4f,', s_out, BURST(cid).mean_dur_ms);
         s_out = sprintf('%s%.4f,', s_out, BURST(cid).burst_spk_total_spk);
         s_out = sprintf('%s%.4f,', s_out, BURST(cid).mean_spk_per_burst);
         
         s_out = sprintf('%s\n',s_out); % NEW LINE
         list_out{lcnt,1} = s_out;
         lcnt = lcnt + 1;
         %

      end
      fclose('all');
   end
end

%
f_out = fopen(s_fname_csv,'w');
fprintf(f_out, '%s', 'Group,Dataset,Trial,Trial_Fine,File,Cell_ID,Mouse,Site,Cell_TYPE,GCID,');
fprintf(f_out, '%s', 'Perc_Bad_WF,');
fprintf(f_out, '%s', 'WF_Peak_mV,');
fprintf(f_out, '%s', 'WF_Swing_mV,');
fprintf(f_out, '%s', 'WF_Width_usec,');
fprintf(f_out, '%s', 'WF_Amp_Assym,');
fprintf(f_out, '%s', 'WF_RMS,');
fprintf(f_out, '%s', 'train_Nspk,');
fprintf(f_out, '%s', 'train_FRpeak,');
fprintf(f_out, '%s', 'train_FRmean,');
fprintf(f_out, '%s', 'train_perc_ISI_u2ms,');
fprintf(f_out, '%s', 'train_CSI_swing,');
fprintf(f_out, '%s', 'train_CSI_peaks,');
fprintf(f_out, '%s', 'train_Lratio,');
fprintf(f_out, '%s', 'train_IsolD,');

fprintf(f_out, '%s', 'B_num_total,');
fprintf(f_out, '%s', 'B_num_per_min,');
fprintf(f_out, '%s', 'B_ibi_sec,');
fprintf(f_out, '%s', 'B_dur_msec,');
fprintf(f_out, '%s', 'Nspk_B_Nspk_train_ratio,');
fprintf(f_out, '%s', 'Spk_per_burst,');

fprintf(f_out, '\n'); % NEW LINE
for ii = 1:length(list_out)
   fprintf(f_out, '%s', list_out{ii});
end
%
fclose('all');


