import abilityTest from './Ability.test';
import legacyReaderNativeTest from './LegacyReaderNative.test';
import agcShadowNativeTest from './AgcShadowNative.test';
import accountAccessNativeTest from './AccountAccessNative.test';
import overdueNativeTest from './OverdueNative.test';
import notificationNativeTest from './NotificationNative.test';
import timeBoundariesTest from '../../../test/TimeBoundaries.test';
import timeRuntimeNativeTest from './TimeRuntimeNative.test';
import experienceNativeTest from './ExperienceNative.test';
import hardeningNativeTest from './HardeningNative.test';
import hardeningKeyboardTest from './HardeningKeyboard.test';

export default function testsuite() {
  abilityTest();
  legacyReaderNativeTest();
  agcShadowNativeTest();
  accountAccessNativeTest();
  overdueNativeTest();
  notificationNativeTest();
  timeBoundariesTest();
  timeRuntimeNativeTest();
  experienceNativeTest();
  hardeningNativeTest();
  hardeningKeyboardTest();
}
