export type UsageTranslationValues = Record<string, string | number | boolean | Date>;

export type UsageTranslator = {
  (key: string, values?: UsageTranslationValues): string;
  has?: (key: string) => boolean;
};

function interpolate(template: string, values?: UsageTranslationValues): string {
  if (!values) return template;
  return template.replace(/\{(\w+)\}/g, (_, k) =>
    k in values ? String(values[k]) : `{${k}}`
  );
}

export function translateUsageOrFallback(
  t: UsageTranslator,
  key: string,
  fallback: string,
  values?: UsageTranslationValues
): string {
  try {
    if (typeof t.has === "function" && !t.has(key)) {
      return interpolate(fallback, values);
    }
    const translated = values ? t(key, values) : t(key);
    if (!translated || translated === key || translated === `usage.${key}`) {
      return interpolate(fallback, values);
    }
    return translated;
  } catch {
    return interpolate(fallback, values);
  }
}
