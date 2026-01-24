/**
 * Detects phone numbers in text and converts them to clickable links
 * Supports various formats including international, national, and simple formats
 */

// Regex patterns for different phone number formats
const phonePatterns = [
  // International format: +55 11 98888-8888, +1 (234) 567-8900
  /(\+\d{1,3}\s?)?\(?\d{2,3}\)?[\s.-]?\d{4,5}[\s.-]?\d{4}/g,
  // Simple format: 11988888888, 1234567890
  /\b\d{10,11}\b/g,
];

/**
 * Checks if a string is a valid phone number
 * @param {string} text - Text to validate
 * @returns {boolean} - Whether the text is a valid phone number
 */
export function isPhoneNumber(text) {
  // Must have at least 10 digits
  const digitsOnly = text.replace(/\D/g, '');
  if (digitsOnly.length < 10 || digitsOnly.length > 15) {
    return false;
  }
  
  // Check against patterns
  return phonePatterns.some(pattern => {
    const match = text.match(pattern);
    return match && match[0] === text;
  });
}

/**
 * Formats a phone number for display
 * @param {string} phoneNumber - Phone number to format
 * @returns {string} - Formatted phone number
 */
export function formatPhoneNumber(phoneNumber) {
  const digitsOnly = phoneNumber.replace(/\D/g, '');
  
  // If already has country code prefix, return as is
  if (phoneNumber.startsWith('+')) {
    return phoneNumber;
  }
  
  // Brazilian format
  if (digitsOnly.length === 11 && digitsOnly.startsWith('0')) {
    return phoneNumber;
  }
  
  return phoneNumber;
}

/**
 * Extracts phone numbers from text
 * @param {string} text - Text to extract phone numbers from
 * @returns {Array<{number: string, start: number, end: number}>} - Array of phone numbers with positions
 */
export function extractPhoneNumbers(text) {
  if (!text) return [];
  
  const numbers = [];
  const seen = new Set();
  
  phonePatterns.forEach(pattern => {
    let match;
    const regex = new RegExp(pattern);
    
    while ((match = regex.exec(text)) !== null) {
      const number = match[0];
      const start = match.index;
      const end = start + number.length;
      
      // Avoid duplicates
      const key = `${start}-${end}`;
      if (!seen.has(key) && isPhoneNumber(number)) {
        seen.add(key);
        numbers.push({ number, start, end });
      }
    }
  });
  
  // Sort by start position
  return numbers.sort((a, b) => a.start - b.start);
}

/**
 * Linkifies phone numbers in HTML string
 * @param {string} html - HTML string to process
 * @param {Function} onPhoneClick - Callback when phone number is clicked
 * @returns {string} - HTML with linkified phone numbers
 */
export function linkifyPhoneNumbers(html, onPhoneClick = null) {
  if (!html) return html;
  
  // Create a temporary div to work with HTML
  const div = document.createElement('div');
  div.innerHTML = html;
  
  // Process text nodes
  const processNode = (node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent;
      const numbers = extractPhoneNumbers(text);
      
      if (numbers.length === 0) return;
      
      // Build new HTML with links
      let result = '';
      let lastIndex = 0;
      
      numbers.forEach(({ number, start, end }) => {
        result += text.substring(lastIndex, start);
        result += `<a href="#" class="phone-number-link text-woot-500 hover:underline" data-phone="${number}">${number}</a>`;
        lastIndex = end;
      });
      
      result += text.substring(lastIndex);
      
      // Replace text node with new HTML
      const span = document.createElement('span');
      span.innerHTML = result;
      node.parentNode.replaceChild(span, node);
    } else if (node.nodeType === Node.ELEMENT_NODE && node.tagName !== 'A') {
      // Recursively process child nodes
      Array.from(node.childNodes).forEach(processNode);
    }
  };
  
  Array.from(div.childNodes).forEach(processNode);
  
  return div.innerHTML;
}

/**
 * Vue directive for linkifying phone numbers
 * Usage: v-linkify-phone="handlePhoneClick"
 */
export const vLinkifyPhone = {
  mounted(el, binding) {
    const originalHTML = el.innerHTML;
    el.innerHTML = linkifyPhoneNumbers(originalHTML);
    
    // Add click handler if provided
    if (binding.value && typeof binding.value === 'function') {
      el.addEventListener('click', (e) => {
        if (e.target.classList.contains('phone-number-link')) {
          e.preventDefault();
          const phoneNumber = e.target.dataset.phone;
          binding.value(phoneNumber);
        }
      });
    }
  },
  updated(el, binding) {
    const originalHTML = el.innerHTML;
    el.innerHTML = linkifyPhoneNumbers(originalHTML);
  },
};



