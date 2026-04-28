export type AnalysisMode = 'promoters_pre' | 'promoters' | 'intervals';
export type TaskMode = AnalysisMode;
export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed';

export interface TaskCreate {
  email: string;
  mode: TaskMode;
  // Frontend-generated UUID reused for upload + task id.
  task_id?: string;
  ic_threshold: number;
  max_match: number;
  promoter_num: number;
  fimo_threshold: number;
  genes_file: string;
  promoter_length?: number;
  utr5?: string;
  promoters_overlap?: string;
  fasta_file?: string;
  gff3_file?: string;
  meme_file?: string;
  premade_index?: string;
}

export interface TaskResponse {
  task_id: string;
  status: TaskStatus;
  mode: TaskMode;
  email: string;
  result_link: string | null;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
  error_message: string | null;
}

export interface TaskListResponse {
  tasks: TaskResponse[];
  total: number;
}

export interface UploadResponse {
  filename: string;
  path: string;
  size: number;
}
