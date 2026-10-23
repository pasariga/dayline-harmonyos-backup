import { DeadlineSubtask, DeadlineTaskView } from '../models/Deadline';

class TaskStackEntry {
  task: DeadlineSubtask;
  level: number;

  constructor(task: DeadlineSubtask, level: number) {
    this.task = task;
    this.level = level;
  }
}

class TaskCompletionCount {
  completed: number;
  total: number;

  constructor(completed: number, total: number) {
    this.completed = completed;
    this.total = total;
  }
}

export class DeadlineProgressService {
  private static buildTaskMap(tasks: DeadlineSubtask[]): Map<string, DeadlineSubtask> {
    const taskMap: Map<string, DeadlineSubtask> = new Map<string, DeadlineSubtask>();
    for (let index: number = 0; index < tasks.length; index++) {
      taskMap.set(tasks[index].id, tasks[index]);
    }
    return taskMap;
  }

  private static sortTasks(tasks: DeadlineSubtask[]): DeadlineSubtask[] {
    return tasks.sort((first: DeadlineSubtask, second: DeadlineSubtask) => {
      if (first.sortOrder !== second.sortOrder) {
        return first.sortOrder - second.sortOrder;
      }
      return first.createdAt - second.createdAt;
    });
  }

  private static buildChildrenMap(tasks: DeadlineSubtask[]): Map<string, DeadlineSubtask[]> {
    const childrenMap: Map<string, DeadlineSubtask[]> = new Map<string, DeadlineSubtask[]>();
    for (let index: number = 0; index < tasks.length; index++) {
      const parentId: string = tasks[index].parentId;
      const children: DeadlineSubtask[] | undefined = childrenMap.get(parentId);
      if (children === undefined) {
        childrenMap.set(parentId, [tasks[index]]);
      } else {
        children.push(tasks[index]);
      }
    }
    childrenMap.forEach((children: DeadlineSubtask[]) => {
      DeadlineProgressService.sortTasks(children);
    });
    return childrenMap;
  }

  static getChildren(tasks: DeadlineSubtask[], parentId: string): DeadlineSubtask[] {
    return DeadlineProgressService.sortTasks(tasks.filter((task: DeadlineSubtask) => task.parentId === parentId));
  }

  private static getCompletionFromGraph(taskMap: Map<string, DeadlineSubtask>,
    childrenMap: Map<string, DeadlineSubtask[]>, taskId: string, visiting: string[],
    countCache: Map<string, TaskCompletionCount>): TaskCompletionCount {
    const cached: TaskCompletionCount | undefined = countCache.get(taskId);
    if (cached !== undefined) {
      return cached;
    }
    if (visiting.indexOf(taskId) >= 0 || visiting.length >= 128) {
      return new TaskCompletionCount(0, 0);
    }
    const task: DeadlineSubtask | undefined = taskMap.get(taskId);
    if (task === undefined) {
      return new TaskCompletionCount(0, 0);
    }
    const children: DeadlineSubtask[] = childrenMap.get(taskId) ?? [];
    if (children.length === 0) {
      const leaf: TaskCompletionCount = new TaskCompletionCount(task.completed ? 1 : 0, 1);
      countCache.set(taskId, leaf);
      return leaf;
    }
    const nextVisiting: string[] = visiting.concat([taskId]);
    let completed: number = 0;
    let total: number = 0;
    for (let index: number = 0; index < children.length; index++) {
      const child: TaskCompletionCount = DeadlineProgressService.getCompletionFromGraph(
        taskMap, childrenMap, children[index].id, nextVisiting, countCache
      );
      completed += child.completed;
      total += child.total;
    }
    const count: TaskCompletionCount = new TaskCompletionCount(completed, total);
    countCache.set(taskId, count);
    return count;
  }

  private static getTaskProgressFromGraph(taskMap: Map<string, DeadlineSubtask>,
    childrenMap: Map<string, DeadlineSubtask[]>, taskId: string, visiting: string[],
    countCache: Map<string, TaskCompletionCount>): number {
    const count: TaskCompletionCount = DeadlineProgressService.getCompletionFromGraph(
      taskMap, childrenMap, taskId, visiting, countCache
    );
    return count.total > 0 ? (count.completed === count.total ? 100 :
      Math.min(99, Math.round(count.completed / count.total * 100))) : 0;
  }

  static getTaskProgress(tasks: DeadlineSubtask[], taskId: string): number {
    return DeadlineProgressService.getTaskProgressFromGraph(
      DeadlineProgressService.buildTaskMap(tasks),
      DeadlineProgressService.buildChildrenMap(tasks),
      taskId,
      [],
      new Map<string, TaskCompletionCount>()
    );
  }

  static calculateDeadlineProgress(tasks: DeadlineSubtask[]): number {
    const taskMap: Map<string, DeadlineSubtask> = DeadlineProgressService.buildTaskMap(tasks);
    const childrenMap: Map<string, DeadlineSubtask[]> = DeadlineProgressService.buildChildrenMap(tasks);
    const countCache: Map<string, TaskCompletionCount> = new Map<string, TaskCompletionCount>();
    const roots: DeadlineSubtask[] = tasks.filter((task: DeadlineSubtask) => {
      return task.parentId.length === 0 || !taskMap.has(task.parentId);
    });
    if (roots.length === 0) {
      return 0;
    }
    let completed: number = 0;
    let total: number = 0;
    for (let index: number = 0; index < roots.length; index++) {
      const count: TaskCompletionCount = DeadlineProgressService.getCompletionFromGraph(
        taskMap, childrenMap, roots[index].id, [], countCache
      );
      completed += count.completed;
      total += count.total;
    }
    return total > 0 ? (completed === total ? 100 :
      Math.min(99, Math.round(completed / total * 100))) : 0;
  }

  static flattenTasks(tasks: DeadlineSubtask[]): DeadlineTaskView[] {
    const views: DeadlineTaskView[] = [];
    const taskMap: Map<string, DeadlineSubtask> = DeadlineProgressService.buildTaskMap(tasks);
    const childrenMap: Map<string, DeadlineSubtask[]> = DeadlineProgressService.buildChildrenMap(tasks);
    const countCache: Map<string, TaskCompletionCount> = new Map<string, TaskCompletionCount>();
    const visited: Map<string, boolean> = new Map<string, boolean>();
    const roots: DeadlineSubtask[] = tasks.filter((task: DeadlineSubtask) => {
      return task.parentId.length === 0 || !taskMap.has(task.parentId);
    });
    DeadlineProgressService.sortTasks(roots);
    const stack: TaskStackEntry[] = [];
    for (let index: number = roots.length - 1; index >= 0; index--) {
      stack.push(new TaskStackEntry(roots[index], 0));
    }
    for (let index: number = 0; index < tasks.length; index++) {
      if (!taskMap.has(tasks[index].parentId) && roots.indexOf(tasks[index]) < 0) {
        stack.push(new TaskStackEntry(tasks[index], 0));
      }
    }
    while (stack.length > 0) {
      const entry: TaskStackEntry = stack.pop() as TaskStackEntry;
      if (visited.has(entry.task.id)) {
        continue;
      }
      visited.set(entry.task.id, true);
      views.push(new DeadlineTaskView(
        entry.task,
        entry.level,
        DeadlineProgressService.getTaskProgressFromGraph(
          taskMap, childrenMap, entry.task.id, [], countCache
        )
      ));
      const children: DeadlineSubtask[] = childrenMap.get(entry.task.id) ?? [];
      for (let childIndex: number = children.length - 1; childIndex >= 0; childIndex--) {
        if (!visited.has(children[childIndex].id)) {
          stack.push(new TaskStackEntry(children[childIndex], Math.min(entry.level + 1, 128)));
        }
      }
    }
    // Cyclic or malformed task groups have no natural root. Keep them visible and bounded
    // instead of recursively overflowing or silently hiding all of their tasks.
    for (let index: number = 0; index < tasks.length; index++) {
      if (!visited.has(tasks[index].id)) {
        stack.push(new TaskStackEntry(tasks[index], 0));
        while (stack.length > 0) {
          const entry: TaskStackEntry = stack.pop() as TaskStackEntry;
          if (visited.has(entry.task.id)) {
            continue;
          }
          visited.set(entry.task.id, true);
          views.push(new DeadlineTaskView(
            entry.task,
            entry.level,
            DeadlineProgressService.getTaskProgressFromGraph(
              taskMap, childrenMap, entry.task.id, [], countCache
            )
          ));
          const children: DeadlineSubtask[] = childrenMap.get(entry.task.id) ?? [];
          for (let childIndex: number = children.length - 1; childIndex >= 0; childIndex--) {
            if (!visited.has(children[childIndex].id)) {
              stack.push(new TaskStackEntry(children[childIndex], Math.min(entry.level + 1, 128)));
            }
          }
        }
      }
    }
    return views;
  }

  static getDescendantIds(tasks: DeadlineSubtask[], taskId: string): string[] {
    const result: string[] = [];
    const visited: Map<string, boolean> = new Map<string, boolean>();
    const childrenMap: Map<string, DeadlineSubtask[]> = DeadlineProgressService.buildChildrenMap(tasks);
    const stack: string[] = [taskId];
    while (stack.length > 0) {
      const currentId: string = stack.pop() as string;
      if (visited.has(currentId)) {
        continue;
      }
      visited.set(currentId, true);
      result.push(currentId);
      const children: DeadlineSubtask[] = childrenMap.get(currentId) ?? [];
      for (let index: number = children.length - 1; index >= 0; index--) {
        if (!visited.has(children[index].id)) {
          stack.push(children[index].id);
        }
      }
    }
    return result;
  }

  static toggleTaskTree(tasks: DeadlineSubtask[], taskId: string, completed: boolean): DeadlineSubtask[] {
    const affectedIds: string[] = DeadlineProgressService.getDescendantIds(tasks, taskId);
    const affectedIdSet: Set<string> = new Set<string>(affectedIds);
    const updatedTasks: DeadlineSubtask[] = tasks.map((task: DeadlineSubtask) => {
      const nextCompleted: boolean = affectedIdSet.has(task.id) ? completed : task.completed;
      return new DeadlineSubtask(
        task.id, task.deadlineId, task.title, nextCompleted, task.createdAt, task.parentId, task.sortOrder
      );
    });

    return DeadlineProgressService.deriveParentStates(updatedTasks);
  }

  static deriveParentStates(tasks: DeadlineSubtask[]): DeadlineSubtask[] {
    const taskMap: Map<string, DeadlineSubtask> = DeadlineProgressService.buildTaskMap(tasks);
    const childrenMap: Map<string, DeadlineSubtask[]> = DeadlineProgressService.buildChildrenMap(tasks);
    const countCache: Map<string, TaskCompletionCount> = new Map<string, TaskCompletionCount>();
    return tasks.map((task: DeadlineSubtask) => {
      const children: DeadlineSubtask[] = childrenMap.get(task.id) ?? [];
      if (children.length === 0) {
        return task;
      }
      const count: TaskCompletionCount = DeadlineProgressService.getCompletionFromGraph(
        taskMap, childrenMap, task.id, [], countCache);
      const derivedCompleted: boolean = count.total > 0 && count.completed === count.total;
      return new DeadlineSubtask(
        task.id, task.deadlineId, task.title, derivedCompleted, task.createdAt, task.parentId, task.sortOrder
      );
    });
  }
}
