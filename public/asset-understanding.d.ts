/** Optional values mean unknown, not false/zero. Semantic strings should be English. */
export interface AssetUnderstanding {
  id?: string;
  filename?: string;
  summary?: string;
  subjects?: string[];
  objects?: string[];
  visualStyle?: string[];
  visibleText?: string[];
  uncertainties?: string[];
  scene?: string[];
  actions?: string[];
  location?: { country?: string; city?: string; poi?: string };
  capture?: {
    cameraMode?: 'drone'|'pov'|'selfie'|'handheld'|'tripod'|'follow'|'car'|'action_camera'|'timelapse';
    shotSize?: 'extreme_wide'|'wide'|'medium'|'close_up'|'extreme_close_up';
    cameraMotion?: 'static'|'push'|'pull'|'pan'|'tilt'|'follow'|'orbit'|'moving';
    slowMotion?: boolean;
  };
  editing?: {
    shotRole?: 'establishing'|'action'|'detail'|'character'|'reaction'|'transition'|'highlight'|'ending';
    /** Normalized 0–1. Only >0.85 earns a highlight marker. */
    importance?: number;
    recommendedUse?: 'hook'|'chapter_open'|'b_roll'|'transition'|'climax'|'ending';
    suggestedDuration?: { min: number; max: number };
  };
  /** Scores accept normalized 0–1 or 0–100, displayed on a 100-point scale. */
  quality?: { overall?: number; sharpness?: number; stability?: number; exposure?: number; composition?: number; issues?: string[] };
  audio?: { hasSpeech?: boolean; speechText?: string; hasUsefulAmbientSound?: boolean; ambientTypes?: string[]; audioQuality?: number; issues?: string[] };
}
