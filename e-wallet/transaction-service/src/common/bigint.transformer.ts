import { ValueTransformer } from 'typeorm';

export const bigintTransformer: ValueTransformer = {
	to: (value: number | null): number | null => value,
	from: (value: string | null | undefined): number =>
		value === null || value === undefined ? 0 : Number(value),
};
