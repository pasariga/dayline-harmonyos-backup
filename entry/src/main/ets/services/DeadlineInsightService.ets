import { Deadline } from '../models/Deadline';
import { AppSettingsRuntime } from './AppSettingsService';
import { LocalizationService } from './LocalizationService';
import { DeadlineOverdueRuntime } from './DeadlineOverdueService';

export class DeadlineInsight {
  progress: number;
  completedHours: number;
  remainingHours: number;
  remainingHoursToDeadline: number;
  riskLevel: string;
  riskLabel: string;
  riskReason: string;
  riskScore: number;
  workloadConfidence: string;

  constructor(progress: number, completedHours: number, remainingHours: number,
    remainingHoursToDeadline: number, riskLevel: string, riskLabel: string,
    riskReason: string, riskScore: number, workloadConfidence: string) {
    this.progress = progress;
    this.completedHours = completedHours;
    this.remainingHours = remainingHours;
    this.remainingHoursToDeadline = remainingHoursToDeadline;
    this.riskLevel = riskLevel;
    this.riskLabel = riskLabel;
    this.riskReason = riskReason;
    this.riskScore = riskScore;
    this.workloadConfidence = workloadConfidence;
  }
}

export class DeadlineInsightService {
  static readonly REMAINING_ESTIMATE_MAX_AGE_MS: number = 14 * 86400000;

  static hasUsableRemainingEstimate(confidence: string): boolean {
    return confidence === 'rough';
  }

  static clampProgress(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(value)));
  }

  static normalizeHours(value: number): number {
    if (!Number.isFinite(value) || value < 0) {
      return 0;
    }
    return value === 0 ? 0 : Math.max(0.5, Math.round(value * 2) / 2);
  }

  static analyze(deadline: Deadline, now: number = Date.now()): DeadlineInsight {
    const progress: number = deadline.completed ? 100 : DeadlineInsightService.clampProgress(deadline.progress);
    // Neither leaf-task counts nor manual progress measure hours already spent.
    const completedHours: number = 0;
    const savedRemaining: number = DeadlineInsightService.normalizeHours(deadline.remainingHours);
    const remainingHoursToDeadline: number = Math.max(0, (deadline.deadlineAt - now) / 3600000);
    let workloadConfidence: string = 'missing';
    if (savedRemaining > 0) {
      if (deadline.remainingState === 'confirmed') {
        workloadConfidence = deadline.remainingUpdatedAt > 0 && now >= deadline.remainingUpdatedAt &&
          now - deadline.remainingUpdatedAt <= DeadlineInsightService.REMAINING_ESTIMATE_MAX_AGE_MS ?
          'rough' : 'stale';
      } else if (deadline.remainingState === 'initial' && progress === 0) {
        workloadConfidence = deadline.remainingUpdatedAt > 0 && now >= deadline.remainingUpdatedAt &&
          now - deadline.remainingUpdatedAt <= DeadlineInsightService.REMAINING_ESTIMATE_MAX_AGE_MS ?
          'rough' : 'stale';
      } else {
        workloadConfidence = 'unmeasured';
      }
    }
    const remainingHours: number = deadline.completed ||
      !DeadlineInsightService.hasUsableRemainingEstimate(workloadConfidence) ? 0 : savedRemaining;

    if (deadline.completed) {
      return new DeadlineInsight(
        progress, completedHours, remainingHours, remainingHoursToDeadline,
        'low', LocalizationService.text('risk_low'), LocalizationService.text('risk_reason_completed'), -1000,
        workloadConfidence
      );
    }

    if (deadline.deadlineAt < now) {
      return new DeadlineInsight(
        progress, completedHours, remainingHours, 0,
        'overdue', LocalizationService.text('common_overdue'), LocalizationService.text('overdue_no_forecast'),
        0, workloadConfidence
      );
    }

    if (workloadConfidence === 'missing') {
      return new DeadlineInsight(
        progress, 0, 0, remainingHoursToDeadline, 'unknown',
        LocalizationService.text('risk_unknown'), LocalizationService.text('risk_reason_missing_workload'),
        100, workloadConfidence
      );
    }

    if (workloadConfidence === 'unmeasured' || workloadConfidence === 'stale') {
      return new DeadlineInsight(
        progress, 0, 0, remainingHoursToDeadline, 'unknown',
        LocalizationService.text('risk_unknown'), LocalizationService.text(workloadConfidence === 'stale' ?
          'risk_reason_stale_work' : 'risk_reason_unmeasured_work'),
        100, workloadConfidence
      );
    }

    const weekdayAvailableHours: number = AppSettingsRuntime.getWeekdayAvailableHours();
    const weekendAvailableHours: number = AppSettingsRuntime.getWeekendAvailableHours();
    const availabilityDescription: string = weekdayAvailableHours === weekendAvailableHours ?
      LocalizationService.text('availability_daily', weekdayAvailableHours) :
      LocalizationService.text('availability_weekday_weekend', weekdayAvailableHours, weekendAvailableHours);
    const availableStudyHours: number = Math.max(
      0.5,
      AppSettingsRuntime.getAvailableHoursBetween(now, deadline.deadlineAt)
    );
    const workloadRatio: number = remainingHours / availableStudyHours;
    const availableHoursText: number = DeadlineInsightService.normalizeHours(availableStudyHours);
    let riskLevel: string = 'low';
    let riskLabel: string = LocalizationService.text('risk_low');
    let riskReason: string = LocalizationService.text('risk_reason_on_track');
    let riskScore: number = workloadRatio * 50;
    const highThreshold: number = 1.25;
    const mediumThreshold: number = 0.75;

    if (remainingHours > 0 && workloadRatio >= highThreshold) {
      riskLevel = 'high';
      riskLabel = LocalizationService.text('risk_high');
      riskReason = LocalizationService.text('risk_reason_capacity_shortfall', remainingHours,
        availabilityDescription, availableHoursText);
      riskScore += 300;
    } else if (remainingHours > 0 && workloadRatio >= mediumThreshold) {
      riskLevel = 'medium';
      riskLabel = LocalizationService.text('risk_medium');
      riskReason = LocalizationService.text('risk_reason_daily_load_high', remainingHours);
      riskScore += 150;
    }

    if (workloadConfidence === 'rough') {
      riskReason = LocalizationService.text('risk_reason_rough_workload', riskReason);
    }

    return new DeadlineInsight(
      progress, completedHours, remainingHours, remainingHoursToDeadline,
      riskLevel, riskLabel, riskReason, riskScore, workloadConfidence
    );
  }

  static analyzePortfolio(deadline: Deadline, deadlines: Deadline[], now: number = Date.now()): DeadlineInsight {
    const insight: DeadlineInsight = DeadlineInsightService.analyze(deadline, now);
    if (deadline.completed || deadline.deadlineAt < now ||
      !DeadlineInsightService.hasUsableRemainingEstimate(insight.workloadConfidence)) {
      return insight;
    }
    let demand: number = 0;
    let hasUnknownDemand: boolean = false;
    for (let index: number = 0; index < deadlines.length; index++) {
      const candidate: Deadline = deadlines[index];
      if (candidate.completed || candidate.deadlineAt < now || candidate.deadlineAt > deadline.deadlineAt) {
        continue;
      }
      const candidateInsight: DeadlineInsight = DeadlineInsightService.analyze(candidate, now);
      if (!DeadlineInsightService.hasUsableRemainingEstimate(candidateInsight.workloadConfidence)) {
        hasUnknownDemand = true;
        continue;
      }
      demand += candidateInsight.remainingHours;
    }
    const capacity: number = AppSettingsRuntime.getAvailableHoursBetween(now, deadline.deadlineAt);
    if (demand > capacity + 0.01) {
      insight.riskLevel = 'high';
      insight.riskLabel = LocalizationService.text('risk_high');
      insight.riskReason = LocalizationService.text('risk_reason_shared_shortfall',
        DeadlineInsightService.normalizeHours(demand), DeadlineInsightService.normalizeHours(capacity));
      insight.riskScore = Math.max(insight.riskScore, 350 + demand - capacity);
    } else if (hasUnknownDemand && insight.riskLevel !== 'high') {
      insight.riskLevel = 'unknown';
      insight.riskLabel = LocalizationService.text('risk_unknown');
      insight.riskReason = LocalizationService.text('risk_reason_shared_unknown');
      insight.riskScore = Math.max(insight.riskScore, 100);
    }
    if (deadlines.some((candidate: Deadline) => DeadlineOverdueRuntime.state(candidate, now) === 'continue')) {
      // Undated late work has no claim in the before-due allocation, but may
      // still use real time. Do not declare the whole portfolio on track.
      if (insight.riskLevel !== 'high') {
        insight.riskLevel = 'unknown';
        insight.riskLabel = LocalizationService.text('risk_unknown');
        insight.riskReason = LocalizationService.text('overdue_capacity_unknown');
      }
    }
    return insight;
  }
}
