import { ValueTransformer } from 'typeorm';

export const bigintTransformer: ValueTransformer = {
  to: (value: any) => value,
  from: (value: any) =>
    value === null || value === undefined ? 0 : Number(value),
};
