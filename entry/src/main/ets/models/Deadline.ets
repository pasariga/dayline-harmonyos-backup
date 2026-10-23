export class Deadline {
  id: string;
  name: string;
  type: string;
  deadlineDate: string;
  deadlineTime: string;
  note: string;
  createdAt: number;
  deadlineAt: number;
  completed: boolean;
  estimatedHours: number;
  remainingHours: number;
  remainingState: string;
  remainingUpdatedAt: number;
  progress: number;
  progressMode: string;
  taskCount: number;
  reminderOffsetMinutes: number;

  constructor(id: string, name: string, type: string, deadlineDate: string, deadlineTime: string,
    note: string, createdAt: number, deadlineAt: number, completed: boolean,
    estimatedHours: number = 0, progress: number = 0, progressMode: string = 'manual', taskCount: number = 0,
    reminderOffsetMinutes: number = 0, remainingHours: number = -1,
    remainingState: string = 'initial', remainingUpdatedAt: number = 0) {
    this.id = id;
    this.name = name;
    this.type = type;
    this.deadlineDate = deadlineDate;
    this.deadlineTime = deadlineTime;
    this.note = note;
    this.createdAt = createdAt;
    this.deadlineAt = deadlineAt;
    this.completed = completed;
    this.estimatedHours = estimatedHours;
    this.remainingHours = remainingHours < 0 ? estimatedHours : remainingHours;
    this.remainingState = remainingState;
    this.remainingUpdatedAt = remainingUpdatedAt === 0 && remainingState === 'initial' ? createdAt : remainingUpdatedAt;
    this.progress = progress;
    this.progressMode = progressMode;
    this.taskCount = taskCount;
    this.reminderOffsetMinutes = reminderOffsetMinutes;
  }
}

export class DeadlineReminderState {
  deadlineId: string;
  reminderId: number;
  scheduledAt: number;
  signature: string;

  constructor(deadlineId: string, reminderId: number, scheduledAt: number, signature: string) {
    this.deadlineId = deadlineId;
    this.reminderId = reminderId;
    this.scheduledAt = scheduledAt;
    this.signature = signature;
  }
}

export class DeadlineSubtask {
  id: string;
  deadlineId: string;
  title: string;
  completed: boolean;
  createdAt: number;
  parentId: string;
  sortOrder: number;

  constructor(id: string, deadlineId: string, title: string, completed: boolean, createdAt: number,
    parentId: string = '', sortOrder: number = 0) {
    this.id = id;
    this.deadlineId = deadlineId;
    this.title = title;
    this.completed = completed;
    this.createdAt = createdAt;
    this.parentId = parentId;
    this.sortOrder = sortOrder;
  }
}

export class DeadlineTaskView {
  task: DeadlineSubtask;
  level: number;
  progress: number;

  constructor(task: DeadlineSubtask, level: number, progress: number) {
    this.task = task;
    this.level = level;
    this.progress = progress;
  }
}

export class DeadlineRouteParams {
  deadlineId: string;

  constructor(deadlineId: string) {
    this.deadlineId = deadlineId;
  }
}
