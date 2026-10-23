import { BusinessError } from '@kit.BasicServicesKit';

// Account/SDK error messages, objects and stacks can contain personal content or
// credentials. Only a bounded numeric diagnostic code may enter public logs.
export class CloudDiagnostic {
  static code(error: Object): string {
    try {
    const code: number = (error as BusinessError)?.code;
    return typeof code === 'number' && Number.isSafeInteger(code) && code >= -2147483648 && code <= 2147483647 ?
      'code=' + code : 'code=unavailable';
    } catch (failure) { return 'code=unavailable'; }
  }
}
