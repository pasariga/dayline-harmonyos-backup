import { common } from '@kit.AbilityKit';
import { CloudAccountService } from './CloudAccountService';
import { DeadlineDatabaseService } from './DeadlineDatabaseService';
import { LegacyImportTrust } from './LegacyCloudImport';
import { FrozenLegacyRead, LegacyReadControl, LegacySnapshotReader, LegacySnapshotSource } from './LegacySnapshotReader';
// No AGC reader or cloudSync is invoked here. Only a future authenticated isolated
// reader with verified server barriers may call this boundary with its result.
export class LegacyCloudMigrationService {
  private static async verifiedAccount(context: common.UIAbilityContext): Promise<string> {
    const verified: string = await CloudAccountService.getCurrentOpenId(context);
    const session = await CloudAccountService.getSession(context);
    if (!session.syncEnabled || session.openId !== verified ||
      (session.lastAccountOpenId.length > 0 && session.lastAccountOpenId !== verified)) {
      throw new Error('The migration account is not the active verified account.');
    }
    return verified;
  }
  // No production caller or network adapter is registered. A future authenticated
  // adapter must supply a frozen export with server-enforced barriers.
  static async readAndStage(context: common.UIAbilityContext, source: LegacySnapshotSource,
    control: LegacyReadControl = new LegacyReadControl()): Promise<string> {
    const result: FrozenLegacyRead = await LegacySnapshotReader.collect(source,
      () => LegacyCloudMigrationService.verifiedAccount(context), control);
    if (control.cancelled) { throw new Error('Old data reading was cancelled before saving.'); }
    return await LegacyCloudMigrationService.acceptVerifiedRead(context, result, control);
  }
  static async acceptVerifiedRead(context: common.UIAbilityContext, source: FrozenLegacyRead,
    control: LegacyReadControl = new LegacyReadControl()): Promise<string> {
    const verified: string = await LegacyCloudMigrationService.verifiedAccount(context);
    if (control.cancelled) { throw new Error('Old data reading was cancelled before saving.'); }
    LegacySnapshotReader.validateJournal(source.journal);
    return await DeadlineDatabaseService.stageLegacyCloudImport(context,
      new LegacyImportTrust(verified, source.accountId, source.sourceId, source.complete,
        source.oldWritesStopped, source.journalComplete), source.payload, source.journal);
  }
}
