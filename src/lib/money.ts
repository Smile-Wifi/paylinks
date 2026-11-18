export const pesosToCentavos = (pesos: number) => Math.round(pesos * 100);
export const formatPHP = (centavos: number) => new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(centavos/100);
