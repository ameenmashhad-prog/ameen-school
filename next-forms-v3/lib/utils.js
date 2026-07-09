export function cloneForm(value) {
  return JSON.parse(JSON.stringify(value));
}

export function generateId(prefix = 'id') {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}`;
}

export function makeOption(baseLabel = 'Option') {
  return {
    id: generateId('option'),
    value: generateId('value'),
    label: {
      ar: `${baseLabel} 1`,
      fa: `${baseLabel} 1`,
      en: `${baseLabel} 1`
    }
  };
}

export function makeField(type, fallbackLabel) {
  const id = generateId('field');
  const field = {
    id,
    type,
    required: false,
    width: 'full',
    label: {
      ar: fallbackLabel,
      fa: fallbackLabel,
      en: fallbackLabel
    },
    placeholder: {
      ar: 'اكتب هنا',
      fa: 'اینجا بنویسید',
      en: 'Type here'
    },
    helpText: {
      ar: '',
      fa: '',
      en: ''
    }
  };

  if (type === 'select') {
    field.options = [
      {
        id: generateId('option'),
        value: 'option_1',
        label: {
          ar: 'الخيار الأول',
          fa: 'گزینه اول',
          en: 'Option One'
        }
      },
      {
        id: generateId('option'),
        value: 'option_2',
        label: {
          ar: 'الخيار الثاني',
          fa: 'گزینه دوم',
          en: 'Option Two'
        }
      }
    ];
  }

  if (type === 'signature') {
    field.placeholder = {
      ar: 'التوقيع هنا',
      fa: 'امضا در اینجا',
      en: 'Sign here'
    };
  }

  if (type === 'file') {
    field.placeholder = {
      ar: 'ارفع الملف',
      fa: 'فایل را بارگذاری کنید',
      en: 'Upload file'
    };
  }

  return field;
}

export function nextVersionStamp() {
  return new Date().toISOString();
}

export function reorderList(items, fromId, toId) {
  const next = [...items];
  const fromIndex = next.findIndex(item => item.id === fromId);
  const toIndex = next.findIndex(item => item.id === toId);
  if (fromIndex === -1 || toIndex === -1 || fromIndex == toIndex) return next;
  const [moved] = next.splice(fromIndex, 1);
  next.splice(toIndex, 0, moved);
  return next;
}
