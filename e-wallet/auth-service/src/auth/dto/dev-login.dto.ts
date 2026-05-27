import { IsOptional, IsString, MaxLength } from 'class-validator';

export class DevLoginDto {
	@IsOptional()
	@IsString()
	@MaxLength(255)
	firebaseUid?: string;

	@IsOptional()
	@IsString()
	@MaxLength(255)
	email?: string;

	@IsOptional()
	@IsString()
	@MaxLength(32)
	phone?: string;

	@IsOptional()
	@IsString()
	@MaxLength(255)
	displayName?: string;
}
