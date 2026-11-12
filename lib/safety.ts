export const safetyConfig={liveReferralsEnabled:false,aiFeaturesEnabled:false,crisisEscalationMode:"simulated" as const,prototypeOnly:true};
export function assertLiveReferralDisabled(){if(!safetyConfig.liveReferralsEnabled)throw new Error("Live referrals are disabled in this prototype.");}
export const safetyNotice="WellBridge AI is a prototype, not an emergency or clinical service. It does not diagnose, prescribe, dispatch help or confirm referrals.";
