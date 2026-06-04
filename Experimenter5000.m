stim_dur = 10;
pre_stim = 2;
itp = 3;
flickerHz = 60;
for ind = 1:5
    
    pause(1)
    %TRigger kry to start Clampex acquisition
    NET.addAssembly('System.Windows.Forms');
    if ind == 1
        System.Windows.Forms.SendKeys.SendWait('%{TAB}');
    end
    pause(0.01);
    System.Windows.Forms.SendKeys.SendWait('^+{1}');
    
    pause(pre_stim); %prestim window
  
  AAGreyScaleFullFieldNoiseFinal2026();
%   AASConeIsoFullFieldNoiseStimFinal2026();
%   AASeededGaussianCheckerboardSConeIsoStimFinal();
%   AASeededGaussianCheckerboardGreyScaleStimFinal();

    pause(stim_dur+1);
    pause(itp)
    sprintf('Trial %d done!',ind)
end
sprintf('Experiment done!')