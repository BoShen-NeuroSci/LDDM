addpath('../utils');
numNode = 1;
[sortNum, myCluster] = RndCtrl(numNode);
mypool = parpool(myCluster, myCluster.NumWorkers);

%% Model fitting with Bayesian Adaptive Direct Search (BADS) optimization algorithm
addpath(genpath('../../bads'));% updated bads, 2022
addpath('../CoreFunctions/');
addpath('./SvrCode/');
out_dir = '../../LDDM_Output/FitRoitman/FitDynmc_OLS_SvrGPU';
if ~exist(out_dir,'dir')
    mkdir(out_dir);
end
%%
% Take data from Roitman & Shadlen, 2002
dataDynmc = load('./RoitmanDataCode/DynmcsData.mat');
dataBhvr = LoadRoitmanData('./RoitmanDataCode');
% Fix random seed for reproducibility
% rng(1);
% change random seed
t = datenum(clock)*10^10 - floor(datenum(clock)*100)*10^8 + sortNum*10^7;
num2str(t);
rng(t);
% Define optimization starting point and bounds
%     a,    b, noise, tauR, tauG, tauD, thresh
LB = [0    0.6   .1   [.01,.01,.01], 65];
UB = [60   2	100  [.5,.5,.5], 100];
PLB = [15  .9	5    [.05 .1 .2], 75];
PUB = [40   1.7	40   [.2 .3 .4], 80];


% Randomize initial starting point inside plausible box
x0 = rand(1,numel(LB)) .* (PUB - PLB) + PLB;

% likelihood function
% parpool(6);
% nLLfun = @(params) LDDMFitBhvr7ParamsX_QMLE_GPU(params, dataBhvr, 102400);
OLS = @(params) LDDM_FitDynmc7Params_OLS_GPU(params, dataDynmc, dataBhvr, 10240);
[fvalbest,~,~] = OLS(x0)
fprintf('test succeeded\n');
% change starting points
Collect = [];
parfor i = 1:myCluster.NumWorkers*1
    !ping -c 1 www.amazon.com
    t = datenum(clock)*10^10 - floor(datenum(clock)*100)*10^8 + sortNum*10^7 + i*10^5;
    %num2str(t);
    rng(t);
    
    % Randomize initial starting point inside plausible box
    x0 = rand(1,numel(LB)) .* (PUB - PLB) + PLB;
    dlmwrite(fullfile(out_dir,'x0List.txt'),[sortNum, i, t, x0],'delimiter','\t','precision','%.6f','-append');
    % fit
    options = bads('defaults');     % Default options
    options.Display = 'iter';
    % For this optimization, we explicitly tell BADS that the objective is
    % noisy (it is not necessary, but it is a good habit)
    options.UncertaintyHandling = true;    % Function is stochastic
    % specify a rough estimate for the value of the standard deviation of the noise in a neighborhood of the solution.
    % options.NoiseSize = 1.81;  % Optional, leave empty if unknown
    % We also limit the number of function evaluations, knowing that this is a
    % simple example. Generally, BADS will tend to run for longer on noisy
    % problems to better explore the noisy landscape.
    % options.MaxFunEvals = 3000;
    
    % Finally, we tell BADS to re-evaluate the target at the returned solution
    % with ** samples (10 by default). Note that this number counts towards the budget
    % of function evaluations.
    options.NoiseFinalSamples = 20;
    [xest,fval,~,output] = bads(OLS,x0,LB,UB,PLB,PUB,[],options);
    dlmwrite(fullfile(out_dir,'RsltList.txt'),[sortNum, i, t, xest fval],'delimiter','\t','precision','%.6f','-append');

    Collect(i).rndseed = t;
    Collect(i).x0 = x0;
    Collect(i).xest = xest;
    Collect(i).fval = fval;
    Collect(i).output = output;    
end
t = datenum(clock)*10^10 - floor(datenum(clock)*100)*10^8 + sortNum*10^7 + i*10^5;
save(fullfile(out_dir,sprintf('CollectRslts%i.mat',t)),'Collect');


if 0
%% hand tuning
% Homedir = 'C:\Users\Bo';
Homedir = '~';
addpath(fullfile(Homedir,'Documents','LDDM','CoreFunctions'));
addpath(fullfile(Homedir,'Documents','LDDM','utils'));
addpath(genpath(fullfile(Homedir,'Documents','LDDM','Fit')));
% cd('G:\My Drive\LDDM\Fit');
cd('/Volumes/GoogleDrive/My Drive/LDDM/Fit');
out_dir = './Rslts/FitDynmc7Params_OLS_SvrGPU';
if ~exist(out_dir,'dir')
    mkdir(out_dir);
end
plot_dir = fullfile(out_dir,'graphics');
if ~exist(plot_dir,'dir')
    mkdir(plot_dir);
end
dataDynmc = load('./RoitmanDataCode/DynmcsData.mat');
dataBhvr = LoadRoitmanData('./RoitmanDataCode');
randseed = 24356545;
rng(randseed);
% a, b, noiseinput, scale, tauRGI, nLL
params = [14.6702    1.2822    6.0202    0.0414    0.4747    0.0101   70.5402];
% params = [0.0036    1.6646   19.1890    0.1944    0.2150    0.1470   78.8105];
%params = [0.0000    0.6040   48.8001    0.0869    0.4686    0.4994   92.8301];
name = sprintf('a%2.2f_b%1.2f_sgm%2.1f_tau%1.2f_%1.2f_%1.2f_thresh%5.2f',params);
if ~exist(fullfile(plot_dir,sprintf('PlotData_%s.mat',name)),'file')
    tic;
    [nLL, Chi2, BIC, AIC, rtmat, choicemat] = LDDMFitBhvr7ParamsX_QMLE_GPU(params, dataBhvr,102400);
    toc
    save(fullfile(plot_dir,sprintf('PlotData_%s.mat',name)),...
        'rtmat','choicemat','params','nLL','Chi2','AIC','BIC');
else
    load(fullfile(plot_dir,sprintf('PlotData_%s.mat',name)));
end

%% Example dynamics
lwd = 1;
mksz = 3;
fontsize = 11;
rng(randseed);
% a, b, noise, scale, tauRGI, nLL
simname = sprintf('LDDM_Dynmc_a%2.2f_b%1.2f_sgm%2.1f_scale%4.1f_tau%1.2f_%1.2f_%1.2f_nLL%4.0f',params);

a = params(1)*eye(2);
b = params(2)*eye(2);
sgm = 5; %.01;
sgmInput = params(3);
tauR = params(5);
tauG = params(6);
tauI = params(7);
Tau = [tauR tauG tauI];
ndt = .09 + .03; % sec, 90ms after stimuli onset, resort to the saccade side,
% the activities reaches peak 30ms before initiation of saccade, according to Roitman & Shadlen
presentt = 0; % changed for this version to move the fitting begin after the time point of recovery
scale = params(4);

predur = 0;
triggert = 0;
dur = 5;
dt =.001;
thresh = 70; %70.8399; % mean(max(m_mr1cD))+1; 
stimdur = dur;
stoprule = 1;
w = [1 1; 1 1];
Rstar = 32; % ~ 32 Hz at the bottom of initial fip, according to Roitman and Shadlen's data
initialvals = [Rstar,Rstar; sum(w(1,:))*Rstar,sum(w(2,:))*Rstar; 0,0];
eqlb = Rstar; % set equilibrium value before task as R^*
Vprior = [1, 1]*(2*mean(w,'all')*eqlb.^2 + (1-a(1)).*eqlb);

Cohr = [0 32 64 128 256 512]/1000; % percent of coherence
c1 = (1 + Cohr)';
c2 = (1 - Cohr)';
cplist = [c1, c2];
mygray = flip(gray(length(cplist)));

h = figure; 
% subplot(2,1,1);
hold on;
filename = sprintf('%s',simname);
randseed = 75245522;
rng(randseed);
for vi = 2:6
    Vinput = cplist(vi,:)*scale;
    [~, ~, R, G, I, Vcourse] = LDDM_RndInput(Vprior, Vinput, w, a, b,...
    sgm, sgmInput*scale, Tau, predur, dur, dt, presentt, triggert, thresh, initialvals, stimdur, stoprule)
    lgd2(vi-1) = plot(R(:,2), 'k-.', 'Color', mygray(vi,:), 'LineWidth',lwd);
    lgd1(vi-1) = plot(R(R(:,1)<=thresh,1), 'k-', 'Color', mygray(vi,:), 'LineWidth',lwd);
end
% legend()
plot([.2, 1.2]/dt,[thresh,thresh], 'k-');
text(600,thresh*1.1,'threshold');
yticks([0,32,70]);
yticklabels({'0','32','70'});
ylabel('Activity (Hz)');
ylim([0,74]);
xticks([0, 500, 1000, 1500]);
xticklabels({'0','.5','1.0','1.5'});
xlim([-50, 1200]);
xlabel('Time (s)');
savefigs(h, filename, plot_dir, fontsize, [2 1.5]);
% 
% subplot(2,1,2); hold on;
% for vi = 2:6
%     Vinput = cplist(vi,:)*scale;
%     [~, ~, R, G, I] = LDDM(Vinput, w, a, b, sgm, Tau, dur,...
%     dt, presentt, triggert, thresh, initialvals, stismdur, stoprule);
%     lgd2(vi-1) = plot(diff(R(:,2)), 'k--', 'Color', mygray(vi+1,:), 'LineWidth',lwd);
%     lgd1(vi-1) = plot(diff(R(:,1)), 'k-', 'Color', mygray(vi+1,:), 'LineWidth',lwd);
% end
% ylabel('Time derivative');
% xticks([0, 500, 1000, 1500]);
% xticklabels({'0','.5','1.0','1.5'});
% xlim([-50, 1800]);
% yticks([-.1,0,.3]);
% ylim([-.1, .35]);
% xlabel('Time (s)');
% savefigs(h, filename, plot_dir, fontsize, [1.8 2.5]);

%% plot RT distribution - fitted
rate = length(rtmat)/1024;
maxrt = max(max(rtmat));
minrt = min(min(rtmat));
%segrt = maxrt - minrt;
bank1 = [];
bank2 = [];
acc = [];
meanrtc = [];
meanrtw = [];
for ii = 1:6
    gap = (dataBhvr.rtrange(ii,2) - dataBhvr.rtrange(ii,1))/dataBhvr.numbins;
    %gap = 1.757/60;
    BinEdge = [minrt:gap:(maxrt+gap)];
    hg = histogram(rtmat(choicemat(:,ii)==1,ii),'BinEdges',BinEdge);
    bank1{ii} = hg.Values/rate;
    hg = histogram(rtmat(choicemat(:,ii)==2,ii),'BinEdges',BinEdge);
    bank2{ii}= hg.Values/rate;
    BinMiddle{ii} = hg.BinEdges(1:end-1) + hg.BinWidth/2;
    acc(ii) = sum(choicemat(:,ii)==1)/(sum(choicemat(:,ii)==1) + sum(choicemat(:,ii)==2));
    meanrtc(ii) = mean(rtmat(choicemat(:,ii)==1,ii));
    meanrtw(ii) = mean(rtmat(choicemat(:,ii)==2,ii));
end
% loading Roitman's data
addpath('../RoitmanDataCode');
ColumnNames608
load T1RT.mat;
x(:,R_RT) = x(:,R_RT)/1000;
cohlist = unique(x(:,R_COH));
maxrt = max(x(:,R_RT));
minrt = min(x(:,R_RT));
segrt = maxrt - minrt;
bins = 30;
BinEdge = [minrt:segrt/bins:maxrt];
bank1r = [];
bank2r = [];
accr = [];
meanrtcr = [];
meanrtwr = [];
for i = 1:length(cohlist)
    Lcoh = x(:,R_COH)==cohlist(i);
    if i == 1
        Dir1 = x(:,R_TRG) == 1;
        Dir2 = x(:,R_TRG) == 2;
        RT_corr = x(Lcoh & Dir1,R_RT);
        RT_wro = x(Lcoh & Dir2, R_RT);
    else
        Corr = x(:,R_DIR) == x(:,R_TRG);
        Wro = x(:,R_DIR) ~= x(:,R_TRG);
        RT_corr = x(Lcoh & Corr,R_RT);
        RT_wro = x(Lcoh & Wro, R_RT);
    end
    accr(i) = numel(RT_corr)/(numel(RT_corr) + numel(RT_wro));
    meanrtcr(i) = mean(RT_corr);
    meanrtwr(i) = mean(RT_wro);
    hg = histogram(RT_corr,'BinEdges',BinEdge);
    bank1r(:,i) = hg.Values;
    if ~isempty(RT_wro)
        hg = histogram(RT_wro,'BinEdges',BinEdge);
        bank2r(:,i) = hg.Values;
    else
        bank2r(:,i) = zeros(1,bins);
    end
end
BinMiddler = hg.BinEdges(1:end-1) + hg.BinWidth/2;
h = figure;
for ii = 1:6
    subplot(6,1,ii);
    % bar(BinMiddler,bank1r(:,ii),'FaceColor','#0072BD','EdgeAlpha',0);
    bar(dataBhvr.bincenter(ii,1:30),dataBhvr.histmat(ii,1:30)*1024,'FaceColor','#0072BD','EdgeAlpha',0);
    hold on;
    % bar(BinMiddler,-bank2r(:,ii),'FaceColor','#D95319','EdgeAlpha',0);
    %plot(BinMiddle{ii},bank1{ii},'c','LineWidth',1.5);
    %plot(BinMiddle{ii},-bank2{ii},'r','LineWidth',1.5);
    bar(dataBhvr.bincenter(ii,1:30),-dataBhvr.histmat(ii,31:60)*1024,'FaceColor','#D95319','EdgeAlpha',0,'EdgeColor','none');
    plot(BinMiddle{ii},bank1{ii},'c','LineWidth',2);
    plot(BinMiddle{ii},-bank2{ii},'m','LineWidth',2);
    if ii == 7
        legend({'','','Correct','Error'},'NumColumns',2,'Location','North');
        legend('boxoff');
    end
    ylim([-60,100]);
    yticks([-50:50:100]);
    yticklabels({'50','0','50','100'});
    xlim([100 1762]/1000);
    xticks([.5,1.0,1.5]);
    if ii == 6
        xticklabels({'.5','1.0','1.5'});
        xlabel('Reaction time (secs)');
    else
        xticklabels({});
    end
    if ii == 1
        ylabel('Frequency');
    end
    % title(sprintf('coherence %2.1f %%',cohlist(ii)*100));
    set(gca,'FontSize',16);
    set(gca,'TickDir','out');
    H = gca;
    H.LineWidth = 1;
    set(gca, 'box','off');
end
%set(gca,'FontSize',18);

h.PaperUnits = 'inches';
h.PaperPosition = [0 0 3.0 10];
%saveas(h,fullfile(plot_dir,sprintf('RTDistrb_%s.fig',name)),'fig');
saveas(h,fullfile(plot_dir,sprintf('RTDistrb_%s.eps',name)),'epsc2');
%% panel a, ditribution of RT and fitted line
lwd = 1;
fontsize = 11;
colorpalette = {'#ef476f','#ffd166','#06d6a0','#118ab2','#073b4c'};
aspect8 = [2, 6.4]; % for the long format RT distribution fitting panels
h = figure;
filename = 'Fig5a';
for ii = 1:6
    subplot(6,1,ii);hold on;
    bar(dataBhvr.bincenter(ii,1:30),dataBhvr.histmat(ii,1:30)*1024,'FaceColor',colorpalette{3},'EdgeAlpha',0);
    bar(dataBhvr.bincenter(ii,1:30),-dataBhvr.histmat(ii,31:60)*1024,'FaceColor',colorpalette{2},'EdgeAlpha',0,'EdgeColor','none');
    plot(BinMiddle{ii},bank1{ii},'Color',colorpalette{4},'LineWidth',lwd);
    plot(BinMiddle{ii},-bank2{ii},'Color',colorpalette{1},'LineWidth',lwd);
    if ii == 7
        legend({'','','Correct','Error'},'NumColumns',2,'Location','North');
        legend('boxoff');
    end
    ylim([-60,100]);
    yticks([-50:50:100]);
    yticklabels({'50','0','50','100'});
    xlim([100 1762]/1000);
    xticks([.5,1.0,1.5]);
    if ii == 6
        xticklabels({'.5','1.0','1.5'});
        xlabel('Reaction time (s)');
    else
        xticklabels({});
    end
    if ii == 1
        ylabel(' ');
    end
    set(gca, 'box','off');
    savefigs(h, filename, plot_dir, fontsize, aspect8);
end
%% aggregated RT & ACC
lwd = 1;
mksz = 3;
fontsize = 11;
Cohr = [0 32 64 128 256 512]/1000;
cplist = Cohr*100;
cplist(1) = 1.1;
h = figure;
filename = sprintf('RT&ACC_%s',name);
subplot(2,1,1);
hold on;
plot(cplist, accr*100, 'xk', 'MarkerSize', mksz+1);
plot(cplist, acc*100,'-k','LineWidth',lwd);
ylim([.45,1]*100);
yticks([50,100]);
xlim([1,100]);
xticks([1,10,100]);
xticklabels({'0','10','100'});
ylabel('Correct (%)');
xlabel('Input coherence (%)');
set(gca, 'XScale', 'log');
legend({'data','model'},'NumColumns',1,'Location','SouthEast','FontSize',fontsize-2);
legend('boxoff');
savefigs(h,filename,plot_dir,fontsize,[2,3.0]);

subplot(2,1,2);
hold on;
lg1 = plot(cplist, meanrtcr, '.k', 'MarkerSize', mksz*3);
lg2 = plot(cplist, meanrtc, '-k','LineWidth',lwd);
lg3 = plot(cplist, meanrtwr, 'ok', 'MarkerSize', mksz);
lg4 = plot(cplist, meanrtw, '--k','LineWidth',lwd);
xlim([1,100]);
xticks([1,10,100]);
xticklabels({'0','10','100'});
yticks([.4,1]);
ylim([.4, 1]);
ylabel('RT (secs)');
xlabel('Input coherence (%)');
set(gca, 'XScale', 'log');
% lgd = legend([lg3,lg1,lg4,lg2],{'','','Error','Correct'},'NumColumns',2,'Location','SouthWest','FontSize',14);
% legend('boxoff');
savefigs(h,filename,plot_dir,fontsize,[2,3.0]);
%% Quantile probability plot for reaction time and choice
lwd = 1.0;
mksz = 3;
fontsize = 11;
x = dataBhvr.proportionmat;
y = dataBhvr.q;
qntls = dataBhvr.qntls;
h = figure; hold on;
acc = [];
for vi = 1:length(x)
    xc = x(vi)*ones(size(y(:,1,vi)));
    xw = 1 - x(vi)*ones(size(y(:,2,vi)));
    lgc = plot(xc,y(:,1,vi),'gx','MarkerSize',mksz+1,'LineWidth',lwd);
    lge = plot(xw,y(:,2,vi),'rx','MarkerSize',mksz+1,'LineWidth',lwd);
    % fitted value
    En(vi) = numel(rtmat(:,vi));
    RT_corr = rtmat(choicemat(:,vi) == 1,vi);
    RT_wro = rtmat(choicemat(:,vi) == 2,vi);
    acc(vi) = numel(RT_corr)/(numel(RT_corr) + numel(RT_wro));
    q(:,1,vi) = quantile(RT_corr,qntls); % RT value on quantiles, correct trial
    q(:,2,vi) = quantile(RT_wro,qntls); % RT value on quantiles, error trial
end
for qi = 1:size(q,1)
    xq = [flip(1-acc), acc]';
    plot(xq,[squeeze(flip(q(qi,2,:)));squeeze(q(qi,1,:))],'k-o','MarkerSize',mksz,'LineWidth',lwd/2);
end
legend([lge,lgc],{'error','correct'},"NumColumns",2,'Location','northeast','FontSize',fontsize-2);
legend('box','off');
xlim([-.05 1.05]);
ylim([.2, 1.4]);
yticks([.2:.4:1.4]);
xlabel('Proportion');
ylabel('RT (s)');
% h.PaperUnits = 'inches';
% h.PaperPosition = [0 0 4 5];
% saveas(h,fullfile(plot_dir,sprintf('Q-QPlot_%s.fig',name)),'fig');
filename = sprintf('QPPlot_%s',name);
% saveas(h,fullfile(plot_dir,filename),'epsc2');
savefigs(h, filename, plot_dir, fontsize, [2.5 2.5]);
%% the original space of QMLE
acc = dataBhvr.proportionmat;
ON = dataBhvr.ON;
OP = dataBhvr.OP;
Oq = dataBhvr.q;
qntls = dataBhvr.qntls;
expd_qntls = [0, qntls, 1];
P = expd_qntls(2:end) - expd_qntls(1:end-1); % proportion in each bin
En = [];
f = [];
h = figure;
for vi = 1:length(acc)
    subplot(6,1,vi); hold on;
    x = 1:10;%Oq(:,1,vi);
    y = ON(:,1,vi).*log(OP(:,1,vi));
    plot(x,y,'gx');
    x = 1:10;%Oq(:,2,vi);
    y = ON(:,2,vi).*log(OP(:,2,vi));
    plot(x,y,'rx');
    set(gca,'YScale','log');
    xlim([0, 11]);
    % ylim(-[1000,1]);
    
    En(vi) = numel(rtmat(:,vi));
    RT_corr = rtmat(choicemat(:,vi) == 1,vi);
    RT_wro = rtmat(choicemat(:,vi) == 2,vi);
    if ~all(isnan(Oq(:,1,vi)))
        tmp = histogram(RT_corr, [0; Oq(:,1,vi); Inf], 'Visible',0);
        EN(:,1,vi) = tmp.Values;
    else
        EN(:,1,vi) = NaN(numel(Oq(:,1,vi))+1,1);
    end
    if ~all(isnan(Oq(:,2,vi)))
        tmp = histogram(RT_wro, [0; Oq(:,2,vi); Inf], 'Visible',0);
        EN(:,2,vi) = tmp.Values;
    else
        EN(:,2,vi) =  NaN(numel(Oq(:,2,vi))+1,1);
    end
    f(:,:,vi) = log((EN(:,:,vi)/En(vi)));
    f(f(:,1,vi) == -Inf,1,vi) = log(1e-10); % set floor value of f at each point, to prevent -Inf
    f(f(:,2,vi) == -Inf,2,vi) = log(1e-10); % set floor value of f at each point, to prevent -Inf
    plot(x,ON(:,1,vi).*f(:,1,vi),'g-');
    plot(x,ON(:,2,vi).*f(:,2,vi),'r-');
end
h.PaperUnits = 'inches';
h.PaperPosition = [0 0 3 10];
%saveas(h,fullfile(plot_dir,sprintf('QMLE_Plot_%s.fig',name)),'fig');
saveas(h,fullfile(plot_dir,sprintf('QMLE_Plot_%s.eps',name)),'epsc2');
%% Sumed Quantile loglikelihodd over coherence
h = figure;
for vi = 1:length(acc)
    Obar(vi) = sum([ON(:,1,vi).*log(OP(:,1,vi)); ON(:,2,vi).*log(OP(:,2,vi))],'omitnan');
    Ebar(vi) = sum([ON(:,1,vi).*(f(:,1,vi)); ON(:,2,vi).*(f(:,2,vi))],'omitnan');
end
bar([Obar; Ebar]','grouped');
h.PaperUnits = 'inches';
h.PaperPosition = [0 0 4 5];
%saveas(h,fullfile(plot_dir,sprintf('SumLL_Plot_%s.fig',name)),'fig');
saveas(h,fullfile(plot_dir,sprintf('SumLL_Plot_%s.eps',name)),'epsc2');
%% proportion at each quantile
h = figure;
for vi = 1:length(acc)
    subplot(6,1,vi); hold on;
    x = 1:10;
    plot(x, OP(:,1,vi),'gx');
    plot(x, -OP(:,2,vi),'rx');
    plot(x, EN(:,1,vi)/En(vi),'g-');
    plot(x, -EN(:,2,vi)/En(vi),'r-');
    %ylim([-.1, .2]);
end
h.PaperUnits = 'inches';
h.PaperPosition = [0 0 3 10];
%saveas(h,fullfile(plot_dir,sprintf('Proportion_Plot_%s.fig',name)),'fig');
saveas(h,fullfile(plot_dir,sprintf('Proportion_Plot_%s.eps',name)),'epsc2');

%% plot time course
params = [9E-06	1.438371	25.389358	3243.067494	0.183473	0.229657	0.324556	16535.000107];
params = [0.0000    0.6040   48.8001    0.0869    0.4686    0.4994   92.8301];
params = [0.0036    1.6646   19.1890    0.1944    0.2150    0.1470   78.8105];
params = [14.6702    1.2822    6.0202    0.0414    0.4747    0.0101   70.5402];
params = [4E-05	1.477076	42.066964	0.138429	0.03566	0.300504	84.082798];
name = sprintf('a%2.2f_b%1.2f_sgm%2.3_tau%1.2f_%1.2f_%1.2f_thresh%5.2f',params);
if ~exist(fullfile(plot_dir,sprintf('PlotDynamic_%s.mat',name)),'file')
    tic;
    [Chi2, N, nLL, BIC, AIC, rtmat, choicemat, sm_mr1c, sm_mr2c, sm_mr1cD, sm_mr2cD] = LDDM_FitDynmc7Params_OLS_GPU(params, dataDynmc, dataBhvr, 10240);
    %sm_mr1c = gather(sm_mr1c);
    save(fullfile(plot_dir,sprintf('PlotDynamic_%s.mat',name)),...
        'rtmat','choicemat','sm_mr1c','sm_mr2c','sm_mr1cD','sm_mr2cD','params');
    toc
else
    load(fullfile(plot_dir, sprintf('PlotDynamic_%s.mat',name)));
end
load('./RoitmanDataCode/DynmcsData.mat');
h = figure;
aspect = [3, 2.5];
fontsize = 10;
lwd = 1;
filename = sprintf('FittedTimeCourse_%s',name);
subplot(1,2,1);hold on;
clear flip;
colvec = flip({[218,166,109]/256,[155 110 139]/256,'#32716d','#af554d','#708d57','#3b5d64'});
for ci = 1:6
    lg(ci) = plot(dot_ax/1000, sm_mr1c(:,ci),'-','Color',colvec{ci},'LineWidth',lwd);
    plot(dot_ax/1000, sm_mr2c(:,ci),'--','Color',colvec{ci},'LineWidth',lwd);
    plot(dot_ax(dot_ax > 190)/1000, m_mr1c(dot_ax > 190,ci),'o','Color',colvec{ci},'MarkerSize',4);
    plot(dot_ax(dot_ax > 190)/1000, m_mr2c(dot_ax > 190,ci),'o','Color',colvec{ci},'MarkerSize',4);
end
set(gca,'TickDir','out');
H = gca;
H.LineWidth = 1;
% ylim([20,60]);
ylim([20,70.5]);
ylabel('Firing rate (sp/s)');
xlabel('Time (secs)');
xlim([-.05, .8]);
xticks([0:.2:.8]);
% set(gca,'FontSize',16);
savefigs(h,filename,plot_dir,fontsize,aspect);
subplot(1,2,2);hold on;
plot([0,0],[20,71],'-k');
for ci = 1:6
    lg(ci) = plot(sac_ax/1000, sm_mr1cD(:,ci),'Color',colvec{ci},'LineWidth',lwd);
    plot(sac_ax/1000, sm_mr2cD(:,ci),'--','Color',colvec{ci},'LineWidth',lwd);
    plot(sac_ax(sac_ax < -30)/1000, m_mr1cD(sac_ax < -30,ci),'o','Color',colvec{ci},'MarkerSize',4);
    plot(sac_ax(sac_ax < -30)/1000, m_mr2cD(sac_ax < -30,ci),'o','Color',colvec{ci},'MarkerSize',4);
end
xlim([-.8, .05]);
set(gca,'TickDir','out');
H = gca;
H.LineWidth = 1;
yticks([]);
set(gca,'ycolor',[1 1 1]);
ylim([20,70.5]);
legend(flip(lg),flip({'0','3.2','6.4','12.8','25.6','51.2'}),'Location','best','FontSize',fontsize-2);
savefigs(h,filename,plot_dir,fontsize,aspect);
saveas(h,fullfile(plot_dir,[filename, '.fig']),'fig');

%% raw data time course
h = figure;
subplot(1,2,1);hold on;
plot(dot_ax, m_mr1c,'o-','LineWidth',1.5);
plot(dot_ax, m_mr2c,'.-','LineWidth',1.5);
set(gca,'FontSize',18);
subplot(1,2,2);hold on;
plot(sac_ax, m_mr1cD,'LineWidth',1.5);
plot(sac_ax, m_mr2cD,'--','LineWidth',1.5);
set(gca,'FontSize',18);
h.PaperUnits = 'inches';
h.PaperPosition = [0 0 5.3 4];
saveas(h,fullfile(plot_dir,sprintf('Data.eps')),'epsc2');
%% plot firing rates at position a,b,c,d 
Cohr = [0 32 64 128 256 512]/1000; % percent of coherence
h = figure;
filename = sprintf('abcd_%s',name);
subplot(2,1,1);hold on;
x = Cohr*100;
y = sm_mr1c(19,:);
plot(x, y,'k.','MarkerSize',16);
p = polyfit(x,y,1);
mdl = fitlm(x,y,'linear')
plot(x,p(1)*x+p(2),'k-');
y = sm_mr2c(19,:);
plot(x, y,'k.','MarkerSize',16);
p = polyfit(x,y,1);
mdl = fitlm(x,y,'linear')
plot(x,p(1)*x+p(2),'k-');
% ylim([10,45]);
xlim([-4,55.2]);
yticks([30:10:60]);
xticks([0:10:50]);
xticklabels({});
ylabel('Firing rates (sp/s)');
% set(gca,'FontSize',12);
% set(gca,'TickDir','out');
% H = gca;
% H.LineWidth = 1;
savefigs(h, filename, plot_dir, fontsize, [2 3]);

subplot(2,1,2);hold on;
y = sm_mr1cD(end-15,:);
plot(x, y,'k.','MarkerSize',16);
p = polyfit(x,y,1);
mdl = fitlm(x,y,'linear')
plot(x,p(1)*x+p(2),'k-');
y = sm_mr2cD(end-15,:);
plot(x, y,'k.','MarkerSize',16);
p = polyfit(x,y,1);
mdl = fitlm(x,y,'linear')
plot(x,p(1)*x+p(2),'k-');
% ylim([0,60]);
xlim([-4,55.2]);
yticks([10:20:70]);
xticks([0:10:50]);
xlabel('Input strength (% coh)');
ylabel('Firing rates (sp/s)');
% set(gca,'FontSize',12);
% set(gca,'TickDir','out');
% H = gca;
% H.LineWidth = 1;
% h.PaperUnits = 'inches';
% h.PaperPosition = [0 0 2.5 4];
%saveas(h,fullfile(plot_dir,sprintf('abcd_%s.fig',name)),'fig');
% saveas(h,fullfile(plot_dir,sprintf('abcd_%s.eps',name)),'epsc2');
savefigs(h, filename, plot_dir, fontsize, [2 3]);

%% disribution of fitted parameters
rslts = dlmread(fullfile(out_dir,'RsltList.txt'));
name = {'a', 'b', 'noise', 'tauR', 'tauG', 'tauI', 'ndt', 'scale', 'sigma of ll'};
h = figure;
for i = 1:9
    subplot(3,3,i);
    hist(rslts(:,i+3));
    xlabel(name{i});
end
h.PaperUnits = 'inches';
h.PaperPosition = [0 0 5.3 4];
saveas(h,fullfile(plot_dir,sprintf('FittedParamsDistribution.eps')),'epsc2');
end

%% noise on the target function
nLLmat = [];
sims = [1024, 1024*5, 10240, 10240*5, 102400];
filename = ['nLLsd_', name];
if ~exist(fullfile(plot_dir,[filename, '.mat']), 'file')
    for sim = 1:5
        for i = 1:10
            [nLL, Chi2, BIC, AIC, rtmat, choicemat] = LDDMFitBhvr7ParamsX_QMLE_GPU(params, dataBhvr, sims(sim));
            nLLmat(sim, i) = nLL;
        end
    end
    save(fullfile(plot_dir,[filename, '.mat']), 'nLLmat','sims','params');
else
    load(fullfile(plot_dir,[filename, '.mat']));
end
h = figure;
plot(sims, std(nLLmat'),'.', 'MarkerSize',18);
set(gca, 'XScale', 'log');
xlabel('N of repetition');
ylabel('Std of nLL');
savefigs(h, filename, plot_dir, fontsize, [2 3]);