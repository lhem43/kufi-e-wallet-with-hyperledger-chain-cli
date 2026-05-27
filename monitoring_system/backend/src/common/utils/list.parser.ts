export type NamedValue = {
  name: string;
  value: string;
};

export function parseNamedList(raw?: string): NamedValue[] {
  if (!raw) {
    return [];
  }

  return raw
    .split(/[;\n]/)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separatorIndex = entry.indexOf('=');
      if (separatorIndex === -1) {
        return {
          name: entry,
          value: entry,
        };
      }

      return {
        name: entry.slice(0, separatorIndex).trim(),
        value: entry.slice(separatorIndex + 1).trim(),
      };
    })
    .filter((entry) => entry.name.length > 0 && entry.value.length > 0);
}
