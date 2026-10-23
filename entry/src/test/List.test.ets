import localUnitTest from './LocalUnit.test';
import corePlanningTest from './CorePlanning.test';
import cloudReliabilityTest from './CloudReliability.test';

import syncProtocolTest from './SyncProtocol.test';
import conflictRecoveryTest from './ConflictRecovery.test';
import legacyCloudImportTest from './LegacyCloudImport.test';
import legacySnapshotReaderTest from './LegacySnapshotReader.test';
import agcShadowTest from './AgcShadow.test';
import overdueTest from './Overdue.test';
import notificationBehaviorTest from './NotificationBehavior.test';
import timeBoundariesTest from './TimeBoundaries.test';
import releaseScopeTest from './ReleaseScope.test';
import experiencePresentationTest from './ExperiencePresentation.test';

export default function testsuite() {
  localUnitTest();
  corePlanningTest();
  cloudReliabilityTest();
  syncProtocolTest();
  conflictRecoveryTest();
  legacyCloudImportTest();
  legacySnapshotReaderTest();
  agcShadowTest();
  overdueTest();
  notificationBehaviorTest();
  timeBoundariesTest();
  releaseScopeTest();
  experiencePresentationTest();
}
