export type AuthenticatedUser = {
  id: string;
  email: string;
  displayName: string;
  title: string;
  locale: string;
  roleCode: string;
  permissions: string[];
};

export type AccessTokenPayload = {
  sub: string;
  email: string;
  roleCode: string;
};
