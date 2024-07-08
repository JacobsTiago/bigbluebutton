import deviceInfo from 'imports/utils/deviceInfo';
import browserInfo from 'imports/utils/browserInfo';
import { createVirtualBackgroundService } from 'imports/ui/services/virtual-background';
import Session from 'imports/ui/services/storage/in-memory';

const BLUR_FILENAME = 'blur.jpg';
const EFFECT_TYPES = {
  BLUR_TYPE: 'blur',
  IMAGE_TYPE: 'image',
  NONE_TYPE: 'none',
}

const MODELS = {
  model96: {
    path: '/resources/tfmodels/segm_lite_v681.tflite',
    segmentationDimensions: {
        height: 96,
        width: 160
    }
  },
  model144: {
    path: '/resources/tfmodels/segm_full_v679.tflite',
    segmentationDimensions: {
        height: 144,
        width: 256
    }
  },
};

const getBasePath = () => {
  const BASE_PATH = window.meetingClientSettings.public.app.cdn
  + window.meetingClientSettings.public.app.basename
  + window.meetingClientSettings.public.app.instanceId;

  return BASE_PATH;
};

const getThumbnailsPath = () => {
  const {
    thumbnailsPath: THUMBNAILS_PATH = '/resources/images/virtual-backgrounds/thumbnails/',
  } = window.meetingClientSettings.public.virtualBackgrounds;

  return THUMBNAILS_PATH;
};

const getImageNames = () => {
  const {
    fileNames: IMAGE_NAMES = ['home.jpg', 'coffeeshop.jpg', 'board.jpg'],
  } = window.meetingClientSettings.public.virtualBackgrounds;

  return IMAGE_NAMES;
};

const getIsStoredOnBBB = () => {
  const {
    storedOnBBB: IS_STORED_ON_BBB = true,
  } = window.meetingClientSettings.public.virtualBackgrounds;

  return IS_STORED_ON_BBB;
};

const createVirtualBackgroundStream = (type, name, isVirtualBackground, stream, customParams) => {
  const buildParams = {
    backgroundType: type,
    backgroundFilename: name,
    isVirtualBackground,
    customParams,
  }

  return createVirtualBackgroundService(buildParams).then((service) => {
    const effect = service.startEffect(stream)
    return { service, effect };
  });
}

const getVirtualBackgroundThumbnail = (name) => {
  if (name === BLUR_FILENAME) {
    return getBasePath() + '/resources/images/virtual-backgrounds/thumbnails/' + name;
  }

  return (getIsStoredOnBBB() ? getBasePath() : '') + getThumbnailsPath() + name;
}

// Stores the last chosen camera effect into the session storage in the following format:
// {
//   type: <EFFECT_TYPES>,
//   name: effect filename, if any
// }
const setSessionVirtualBackgroundInfo = (type, name, deviceId) => (
  Session.setItem(`VirtualBackgroundInfo_${deviceId}`, { type, name })
);

const getSessionVirtualBackgroundInfo = (deviceId) => (
  Session.getItem(`VirtualBackgroundInfo_${deviceId}`) || {
    type: EFFECT_TYPES.NONE_TYPE,
  }
);

const getSessionVirtualBackgroundInfoWithDefault = (deviceId) => (
  Session.getItem(`VirtualBackgroundInfo_${deviceId}`) || {
    type: EFFECT_TYPES.BLUR_TYPE,
    name: BLUR_FILENAME,
  }
);

const isVirtualBackgroundSupported = () => {
  return !(deviceInfo.isIos || browserInfo.isSafari);
}

const getVirtualBgImagePath = () => {
  const {
    imagesPath: IMAGES_PATH = '/resources/images/virtual-backgrounds/',
  } = window.meetingClientSettings.public.virtualBackgrounds;

  return (getIsStoredOnBBB() ? getBasePath() : '') + IMAGES_PATH;
}

export {
  getBasePath,
  getImageNames,
  MODELS,
  BLUR_FILENAME,
  EFFECT_TYPES,
  setSessionVirtualBackgroundInfo,
  getSessionVirtualBackgroundInfo,
  getSessionVirtualBackgroundInfoWithDefault,
  isVirtualBackgroundSupported,
  createVirtualBackgroundStream,
  getVirtualBackgroundThumbnail,
  getVirtualBgImagePath,
};