'use client';

import { useState, useEffect } from 'react';
import { taskApi } from '@/lib/api';
import { TaskResponse } from '@/lib/types';
import TaskCard from '@/components/TaskCard';
import { useRouter } from 'next/navigation';
import { useTranslation } from '@/lib/i18n';

export default function TasksPage() {
  const router = useRouter();
  const { t } = useTranslation();
  const [tasks, setTasks] = useState<TaskResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchEmail, setSearchEmail] = useState('');
  const [activeEmailFilter, setActiveEmailFilter] = useState('');

  useEffect(() => {
    if (!activeEmailFilter) return;
    if (!tasks.some((task) => task.status === 'pending' || task.status === 'running')) {
      return;
    }

    const interval = setInterval(() => {
      fetchTasks(activeEmailFilter, false);
    }, 5000);

    return () => clearInterval(interval);
  }, [tasks, activeEmailFilter]);

  const fetchTasks = async (filterEmail: string, showLoading = true) => {
    if (showLoading) setLoading(true);
    try {
      const response = await taskApi.list(filterEmail);
      setTasks(response.tasks);
    } catch (error) {
      console.error('Failed to fetch tasks:', error);
    } finally {
      if (showLoading) setLoading(false);
    }
  };

  const handleSearch = () => {
    const filterEmail = searchEmail.trim();
    if (!filterEmail) return;
    setActiveEmailFilter(filterEmail);
    fetchTasks(filterEmail);
  };

  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">{t('tasks.title')}</h1>
        <button
          onClick={() => router.push('/submit')}
          className="btn-primary"
        >
          {t('tasks.new')}
        </button>
      </div>

      <div className="card mb-6">
        <label className="block text-sm text-slate-600 mb-2">
          {t('tasks.search.label')}
        </label>
        <div className="flex gap-4">
          <input
            type="email"
            className="input-field flex-1"
            placeholder={t('tasks.search.placeholder')}
            value={searchEmail}
            onChange={(e) => setSearchEmail(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
          />
          <button
            onClick={handleSearch}
            disabled={!searchEmail.trim()}
            className="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {t('tasks.search.button')}
          </button>
        </div>
      </div>

      {!activeEmailFilter ? (
        <div className="text-center py-12 text-slate-500">
          {t('tasks.empty.no_email')}
        </div>
      ) : loading ? (
        <div className="text-center py-12 text-slate-500">{t('tasks.empty.loading')}</div>
      ) : tasks.length === 0 ? (
        <div className="text-center py-12 text-slate-500">
          {t('tasks.empty.none_prefix')} <span className="font-mono">{activeEmailFilter}</span>.
        </div>
      ) : (
        <div className="space-y-4">
          {tasks.map((task) => (
            <TaskCard
              key={task.task_id}
              task={task}
              onSelect={() => router.push(`/tasks/${task.task_id}`)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
