import { IsNotEmpty, IsString } from 'class-validator';

export class VerifyIdTokenDto {
	@IsString()
	@IsNotEmpty()
	idToken: string;
}
