trigger AccountAddressTrigger1 on Account (before update) {
  system.debug('james adding second');
}