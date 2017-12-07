%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright (C) 2011-2014 by the Human Connectome Project, WU-Minn Consortium (1U54MH091657)
%
% This file is part of megconnectome.
%
% megconnectome is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% megconnectome is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with megconnectome.  If not, see <http://www.gnu.org/licenses/>.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% setup the execution environment
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
opengl software;

% ensure that the time and date of execution are not stored in the provenance information
global ft_default
ft_default.trackcallinfo = 'no';

% allow the user to specify the path where additional data is present, e.g. the channel layout or anatomy files
if exist('path', 'var')
    addpath(path)
end

if ~exist('filename', 'var')
    error('filename should be specified')
end

% the filename is assumed to be something like
% 'rawdatadir/Phase1MEG/Subjects/CP10018/Experiments/CP10018_MEG/Scans/1-Rnoise_MNN_V1/Resources/4D/c,rfDC'
tok = tokenize(filename, '/');

if ~exist('subjectid', 'var')
    subjectid = tok{end-7};
end

if ~exist('experimentid', 'var')
    experimentid = tok{end-5};
end

% if ~exist('scanid', 'var')
%     scanid = tok{end-3};
% end

scanid={'3-Restin' ; '4-Restin' ; '5-Restin'};

if ~exist('pipelinedatadir', 'var')
    pipelinedatadir = hcp_pathdef;
end

% print the matlab and megconnectome version to screen for provenance
ver('megconnectome')

% % print the value of all local variables to screen for provenance
% w = whos;
% w = {w.name};
% w = setdiff(w, {'w', 'ans'});
% for i=1:length(w)
%     fprintf(hcp_printstruct(w{i}, eval(w{i})));
% end

% change to the location of the processed data (input and output)
cd(pipelinedatadir)

% hcp_check_pipelineoutput('anatomy', 'subject', subjectid);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% execute the pipeline
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

smodel_type = {'2D';'3D'}; dimindx=1; % 1 for 2D cortical sheet and 2 for 3D gird
griddim = {'4mm';'6mm';'8mm'}; gridindx=1; % $ 1,2,3 for 3D 4mm,6mm and 8mm grid

if(strcmp(smodel_type{dimindx},'2D'))
    hcp_read_matlab([subjectid '_MEG_anatomy_sourcemodel_2d']);
    sourcemodelsubj = sourcemodel2d;
    sourcemodel_type=smodel_type{dimindx};
    head=ft_read_headshape([subjectid '.L.midthickness.8k_fs_LR.surf.gii']);
    head2=ft_read_headshape([subjectid '.R.midthickness.8k_fs_LR.surf.gii']);
    sourcemodel=head;
    sourcemodel.pnt=[head.pnt ; head2.pnt];
    sourcemodel.tri=[head.tri ; head2.tri];
elseif(strcmp(smodel_type{dimindx},'3D'))
    %     junk=hcp_read_matlab([subjectid '_anatomy_sourcemodel3D' griddim{gridindx}]);
    %     gridname = 'sourcemodel3d';
    %     sourcemodelsubj=junk.(gridname);
    %     sourcemodelsubj=ft_convert_units(sourcemodelsubj,'mm');
    
    hcp_read_matlab(['standard_sourcemodel3d' griddim{gridindx}]);
    sourcemodel_type=[smodel_type{dimindx} griddim{gridindx}];
end

bands=[1 2 3 4 5 6 7];
blp_bands = [ 1.3 4 ; 3 8 ; 6 15 ; 12.5 28.5 ; 30 75 ; 70 150 ; 1 150];
band_prefix={
    'delta'
    'theta'
    'alpha'
    'beta'
    'lowgamma'
    'highgamma'
    'whole'
    };

window_corr=25; %window for stationary corr in sec
Fs=50;
window_corr2=window_corr*Fs;
source_blp=[];
for ib=bands
    nwin_tot=0;
    for i_scan=1:3
        clear source_blp
        
        resultprefix = sprintf('%s_%s', experimentid, scanid{i_scan});
        
        outputfile=[experimentid '_blpcorr_' band_prefix{ib}];
        
        %     hcp_check_pipelineoutput('icapowenv', 'subject', subjectid, 'experiment', experimentid, 'scan', scanid,'band',band_prefix{ib});
        outstr=[resultprefix '_blp_' sourcemodel_type '_' band_prefix{ib}];
        disp(['loading blp file ' outstr])
        hcp_read_matlab([resultprefix '_blp_' sourcemodel_type '_' band_prefix{ib}])
        
        if (i_scan==1)
            connect_stat=zeros(size(source_blp.power,1));
        end
        ntp=size(source_blp.power,2);
        nwin=floor(ntp/(Fs*window_corr))
        for i=1:nwin
            vect=[((i-1)*window_corr2)+1:window_corr2*i];
            connect_stat=corr(source_blp.power(:,vect)')+connect_stat;
        end
        nwin_tot=nwin_tot+nwin;
    end
    
    connect_stat=connect_stat/nwin_tot;
    connect_stat = cast(connect_stat,'single');
    
    atlas_rsn_l=ft_read_atlas('RSN-networks.L.8k_fs_LR.label.gii');
    atlas_rsn_r=ft_read_atlas('RSN-networks.R.8k_fs_LR.label.gii');
    indxvoxels=[];
    jn=0;
    for in=3:numel(atlas_rsn_r.parcellation4label)
        jn=jn+1;
        networkl{jn}=atlas_rsn_r.parcellation4label{in};
        nindxl=find(strcmp(atlas_rsn_l.parcellation4label,atlas_rsn_r.parcellation4label{in}));
        if ~isempty(nindxl)
            indxvoxels=[indxvoxels ; find(atlas_rsn_l.parcellation4==nindxl)];
        end
        indxvoxels=[indxvoxels ; (find(atlas_rsn_r.parcellation4==in)+numel(atlas_rsn_l.parcellation4))];
        if (jn==1)
            net_max(jn,:)=[1 numel(indxvoxels)];
        else
            net_max(jn,:)=[(net_max(jn-1,2)+1) numel(indxvoxels)];
        end
    end
    
    connect.networkl=networkl;
    connect.connect_stat=connect_stat;
    connect.net_extr=net_max;
    connect.indxvoxels=indxvoxels;
    hcp_write_matlab(outputfile)
    
    dofig='yes';
    if strcmp(dofig,'yes')
        figure
        imagesc(connect_stat(indxvoxels,indxvoxels));
        caxis([0.5 1])
        colorbar
        imgname = [outputfile '.png'];
        hcp_write_figure(imgname, gcf)
                
       close all
    end
    clear source_blp connect
end