import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { TaskResponse } from './types';

interface TaskStore {
  currentTask: TaskResponse | null;
  tasks: TaskResponse[];
  loading: boolean;
  error: string | null;

  setCurrentTask: (task: TaskResponse | null) => void;
  setTasks: (tasks: TaskResponse[]) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  addTask: (task: TaskResponse) => void;
  updateTask: (taskId: string, updates: Partial<TaskResponse>) => void;
}

export const useTaskStore = create<TaskStore>((set) => ({
  currentTask: null,
  tasks: [],
  loading: false,
  error: null,

  setCurrentTask: (task) => set({ currentTask: task }),
  setTasks: (tasks) => set({ tasks }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  addTask: (task) => set((state) => ({ tasks: [task, ...state.tasks] })),
  updateTask: (taskId, updates) =>
    set((state) => ({
      tasks: state.tasks.map((t) => (t.task_id === taskId ? { ...t, ...updates } : t)),
      currentTask:
        state.currentTask?.task_id === taskId
          ? { ...state.currentTask, ...updates }
          : state.currentTask,
    })),
}));

interface SettingsStore {
  mode: 'promoters_pre' | 'promoters' | 'intervals';
  email: string;
  setMode: (mode: 'promoters_pre' | 'promoters' | 'intervals') => void;
  setEmail: (email: string) => void;
}

export const useSettingsStore = create<SettingsStore>()(
  persist(
    (set) => ({
      mode: 'promoters_pre',
      email: '',
      setMode: (mode) => set({ mode }),
      setEmail: (email) => set({ email }),
    }),
    {
      name: 'pmet-settings',
      partialize: (state) => ({ mode: state.mode }),
    },
  ),
);
