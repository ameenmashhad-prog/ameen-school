export function cloneForm(value) {
  return JSON.parse(JSON.stringify(value));
}

export function makeField(type, label) {
  const id = `field_${Math.random().toString(36).slice(2, 9)}`;
  return {
    id,
    type,
    required: false,
    label: {
      ar: label,
      fa: label,
      en: label
    },
    placeholder: {
      ar: 'اكتب هنا',
      fa: 'اینجا بنویسید',
      en: 'Type here'
    }
  };
}

export function nextVersionStamp() {
  return new Date().toISOString();
}
