"""
Economic Data Collector - FRED API Alternative Implementation

This module provides a complete implementation for collecting economic indicators
using free and low-cost APIs as alternatives to FRED API.

Author: Claude
Date: 2025-11-13
"""

import yfinance as yf
from fredapi import Fred
import requests
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Tuple
import time
from functools import wraps
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def rate_limit(calls_per_minute: int):
    """
    Decorator to rate limit API calls

    Args:
        calls_per_minute: Maximum number of calls allowed per minute
    """
    min_interval = 60.0 / calls_per_minute
    last_called = [0.0]

    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            elapsed = time.time() - last_called[0]
            left_to_wait = min_interval - elapsed
            if left_to_wait > 0:
                time.sleep(left_to_wait)
            ret = func(*args, **kwargs)
            last_called[0] = time.time()
            return ret
        return wrapper
    return decorator


def retry_with_exponential_backoff(
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0
):
    """
    Retry decorator with exponential backoff

    Args:
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay between retries in seconds
        max_delay: Maximum delay between retries in seconds
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_retries - 1:
                        logger.error(f"Max retries reached for {func.__name__}: {e}")
                        raise

                    delay = min(base_delay * (2 ** attempt), max_delay)
                    logger.warning(f"Attempt {attempt + 1} failed, retrying in {delay}s: {e}")
                    time.sleep(delay)
        return wrapper
    return decorator


class EconomicDataCollector:
    """
    Collects economic indicators from various free and low-cost APIs
    """

    def __init__(self, fred_api_key: Optional[str] = None):
        """
        Initialize the data collector

        Args:
            fred_api_key: FRED API key (optional but recommended)
                         Get one at: https://fred.stlouisfed.org/docs/api/api_key.html
        """
        self.fred = Fred(api_key=fred_api_key) if fred_api_key else None
        logger.info("EconomicDataCollector initialized")

    @retry_with_exponential_backoff(max_retries=3)
    @rate_limit(calls_per_minute=10)
    def get_vix(self, period: str = "1y") -> pd.Series:
        """
        Get VIX (Volatility Index) from Yahoo Finance

        Args:
            period: Data period (e.g., "1y", "6mo", "1mo")

        Returns:
            pandas Series with VIX values
        """
        logger.info("Fetching VIX data from Yahoo Finance")
        vix = yf.Ticker("^VIX")
        data = vix.history(period=period)['Close']
        logger.info(f"Successfully fetched VIX data: {len(data)} records")
        return data

    @retry_with_exponential_backoff(max_retries=3)
    def get_high_yield_spread(self, start_date: Optional[str] = None) -> pd.Series:
        """
        Get High Yield Spread from FRED
        Series: BAMLH0A0HYM2 - ICE BofA US High Yield Index Option-Adjusted Spread

        Args:
            start_date: Start date in 'YYYY-MM-DD' format

        Returns:
            pandas Series with high yield spread values in percentage points
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        logger.info("Fetching High Yield Spread from FRED")
        data = self.fred.get_series('BAMLH0A0HYM2', observation_start=start_date)
        logger.info(f"Successfully fetched High Yield Spread: {len(data)} records")
        return data

    @retry_with_exponential_backoff(max_retries=3)
    def get_yield_curve(self, start_date: Optional[str] = None) -> pd.Series:
        """
        Calculate Yield Curve (10Y - 2Y Treasury spread)

        Args:
            start_date: Start date in 'YYYY-MM-DD' format

        Returns:
            pandas Series with yield curve spread in percentage points
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        logger.info("Fetching Treasury yields for yield curve calculation")
        treasury_10y = self.fred.get_series('DGS10', observation_start=start_date)
        treasury_2y = self.fred.get_series('DGS2', observation_start=start_date)

        # Align the series
        yield_curve = treasury_10y - treasury_2y
        yield_curve = yield_curve.dropna()

        logger.info(f"Successfully calculated yield curve: {len(yield_curve)} records")
        return yield_curve

    @retry_with_exponential_backoff(max_retries=3)
    @rate_limit(calls_per_minute=10)
    def get_fear_greed(self) -> Dict[str, Any]:
        """
        Get Fear & Greed Index from CNN

        Returns:
            Dictionary with fear & greed data
        """
        logger.info("Fetching Fear & Greed Index from CNN")
        date_str = datetime.now().strftime('%Y-%m-%d')
        url = f'https://production.dataviz.cnn.io/index/fearandgreed/graphdata/{date_str}'

        response = requests.get(url, timeout=10)
        response.raise_for_status()
        data = response.json()

        result = {
            'score': data['fear_and_greed']['score'],
            'rating': data['fear_and_greed']['rating'],
            'timestamp': data['fear_and_greed']['timestamp']
        }

        logger.info(f"Successfully fetched Fear & Greed: {result['score']} ({result['rating']})")
        return result

    @retry_with_exponential_backoff(max_retries=3)
    @rate_limit(calls_per_minute=10)
    def get_sp500_drawdown(self, period: str = "1y") -> pd.Series:
        """
        Calculate S&P 500 Drawdown from peak

        Args:
            period: Data period (e.g., "1y", "6mo", "1mo")

        Returns:
            pandas Series with drawdown values (negative percentages)
        """
        logger.info("Calculating S&P 500 drawdown")
        sp500 = yf.Ticker("^GSPC")
        prices = sp500.history(period=period)['Close']

        running_max = prices.expanding().max()
        drawdown = (prices - running_max) / running_max

        logger.info(f"Successfully calculated S&P 500 drawdown: current = {drawdown.iloc[-1]:.2%}")
        return drawdown

    @retry_with_exponential_backoff(max_retries=3)
    @rate_limit(calls_per_minute=10)
    def get_market_breadth(self) -> pd.DataFrame:
        """
        Get Market Breadth (Advance-Decline) data from Unicorn Research

        Returns:
            pandas DataFrame with market breadth metrics
        """
        logger.info("Fetching market breadth data from Unicorn Research")
        url = 'http://unicorn.us.com/advdec/advdec.txt'

        df = pd.read_csv(url)

        # Calculate breadth metrics
        df['breadth_ratio'] = df['advances'] / (df['advances'] + df['declines'])
        df['advance_decline_diff'] = df['advances'] - df['declines']
        df['advance_decline_line'] = df['advance_decline_diff'].cumsum()

        logger.info(f"Successfully fetched market breadth data: {len(df)} records")
        return df

    @retry_with_exponential_backoff(max_retries=3)
    @rate_limit(calls_per_minute=10)
    def get_russell_drawdown(self, period: str = "1y") -> pd.Series:
        """
        Calculate Russell 3000 Drawdown (proxy for Russell 5000)
        Note: Russell 5000 not directly available, using Russell 3000 (^RUA)

        Args:
            period: Data period (e.g., "1y", "6mo", "1mo")

        Returns:
            pandas Series with drawdown values (negative percentages)
        """
        logger.info("Calculating Russell 3000 drawdown (Russell 5000 proxy)")
        russell = yf.Ticker("^RUA")
        prices = russell.history(period=period)['Close']

        running_max = prices.expanding().max()
        drawdown = (prices - running_max) / running_max

        logger.info(f"Successfully calculated Russell drawdown: current = {drawdown.iloc[-1]:.2%}")
        return drawdown

    @retry_with_exponential_backoff(max_retries=3)
    def get_ted_spread(self, start_date: Optional[str] = None) -> Tuple[pd.Series, pd.Series]:
        """
        Get TED Spread (DISCONTINUED as of 2022-01-31)
        Returns both historical TED spread and modern SOFR-based alternative

        Args:
            start_date: Start date in 'YYYY-MM-DD' format

        Returns:
            Tuple of (historical_ted_spread, modern_spread)
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        logger.info("Fetching TED Spread data (discontinued)")

        # Historical TED spread (discontinued)
        ted_spread = self.fred.get_series('TEDRATE', observation_start=start_date)

        # Modern alternative: SOFR - 3-month T-Bill
        sofr = self.fred.get_series('SOFR', observation_start='2022-01-01')
        tbill_3m = self.fred.get_series('DTB3', observation_start='2022-01-01')

        # Align the series
        modern_spread = (sofr - tbill_3m).dropna()

        logger.info(f"Fetched TED Spread: historical={len(ted_spread)}, modern={len(modern_spread)} records")
        return ted_spread, modern_spread

    @retry_with_exponential_backoff(max_retries=3)
    def get_sofr_ois_spread(self, start_date: Optional[str] = None) -> pd.Series:
        """
        Calculate SOFR-OIS Spread (using Fed Funds rate as OIS proxy)

        Args:
            start_date: Start date in 'YYYY-MM-DD' format

        Returns:
            pandas Series with SOFR-OIS spread in basis points
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        logger.info("Calculating SOFR-OIS spread")
        sofr = self.fred.get_series('SOFR', observation_start=start_date)
        fed_funds = self.fred.get_series('DFF', observation_start=start_date)

        # Calculate spread in basis points
        spread = ((sofr - fed_funds) * 100).dropna()

        logger.info(f"Successfully calculated SOFR-OIS spread: {len(spread)} records")
        return spread

    @retry_with_exponential_backoff(max_retries=3)
    def get_bbb_spread(self, start_date: Optional[str] = None) -> pd.Series:
        """
        Get BBB Corporate Spread from FRED
        Series: BAMLC0A4CBBB - ICE BofA BBB US Corporate Index Option-Adjusted Spread

        Args:
            start_date: Start date in 'YYYY-MM-DD' format

        Returns:
            pandas Series with BBB spread values in percentage points
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        logger.info("Fetching BBB Spread from FRED")
        data = self.fred.get_series('BAMLC0A4CBBB', observation_start=start_date)
        logger.info(f"Successfully fetched BBB Spread: {len(data)} records")
        return data

    @retry_with_exponential_backoff(max_retries=3)
    def get_sahm_rule(self, start_date: Optional[str] = None, real_time: bool = False) -> pd.Series:
        """
        Get Sahm Rule Recession Indicator from FRED

        Args:
            start_date: Start date in 'YYYY-MM-DD' format
            real_time: If True, use real-time version (SAHMREALTIME), else use current (SAHMCURRENT)

        Returns:
            pandas Series with Sahm Rule values
            Note: Values >= 0.5 typically signal recession start
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        series_id = 'SAHMREALTIME' if real_time else 'SAHMCURRENT'
        logger.info(f"Fetching Sahm Rule ({series_id}) from FRED")
        data = self.fred.get_series(series_id, observation_start=start_date)
        logger.info(f"Successfully fetched Sahm Rule: {len(data)} records, current={data.iloc[-1]:.3f}")
        return data

    @retry_with_exponential_backoff(max_retries=3)
    def get_jobless_claims(self, start_date: Optional[str] = None,
                          continued: bool = False) -> pd.Series:
        """
        Get Jobless Claims from FRED

        Args:
            start_date: Start date in 'YYYY-MM-DD' format
            continued: If True, get continued claims (CCSA), else initial claims (ICSA)

        Returns:
            pandas Series with jobless claims (thousands of persons)
        """
        if not self.fred:
            raise ValueError("FRED API key required for this indicator")

        series_id = 'CCSA' if continued else 'ICSA'
        claim_type = "Continued" if continued else "Initial"

        logger.info(f"Fetching {claim_type} Jobless Claims from FRED")
        data = self.fred.get_series(series_id, observation_start=start_date)
        logger.info(f"Successfully fetched {claim_type} Claims: {len(data)} records")
        return data

    def collect_all_indicators(self,
                               start_date: Optional[str] = None,
                               period: str = "1y") -> Dict[str, Any]:
        """
        Collect all economic indicators

        Args:
            start_date: Start date for time series data (YYYY-MM-DD)
            period: Period for Yahoo Finance data (e.g., "1y", "6mo")

        Returns:
            Dictionary containing all indicators
        """
        logger.info("Collecting all economic indicators...")
        indicators = {}
        errors = {}

        # VIX
        try:
            indicators['vix'] = self.get_vix(period=period)
        except Exception as e:
            logger.error(f"Failed to get VIX: {e}")
            errors['vix'] = str(e)

        # High Yield Spread
        try:
            indicators['high_yield_spread'] = self.get_high_yield_spread(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get High Yield Spread: {e}")
            errors['high_yield_spread'] = str(e)

        # Yield Curve
        try:
            indicators['yield_curve'] = self.get_yield_curve(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get Yield Curve: {e}")
            errors['yield_curve'] = str(e)

        # Fear & Greed
        try:
            indicators['fear_greed'] = self.get_fear_greed()
        except Exception as e:
            logger.error(f"Failed to get Fear & Greed: {e}")
            errors['fear_greed'] = str(e)

        # S&P 500 Drawdown
        try:
            indicators['sp500_drawdown'] = self.get_sp500_drawdown(period=period)
        except Exception as e:
            logger.error(f"Failed to get S&P 500 Drawdown: {e}")
            errors['sp500_drawdown'] = str(e)

        # Market Breadth
        try:
            indicators['market_breadth'] = self.get_market_breadth()
        except Exception as e:
            logger.error(f"Failed to get Market Breadth: {e}")
            errors['market_breadth'] = str(e)

        # Russell Drawdown
        try:
            indicators['russell_drawdown'] = self.get_russell_drawdown(period=period)
        except Exception as e:
            logger.error(f"Failed to get Russell Drawdown: {e}")
            errors['russell_drawdown'] = str(e)

        # TED Spread
        try:
            indicators['ted_spread_historical'], indicators['ted_spread_modern'] = \
                self.get_ted_spread(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get TED Spread: {e}")
            errors['ted_spread'] = str(e)

        # SOFR-OIS Spread
        try:
            indicators['sofr_ois_spread'] = self.get_sofr_ois_spread(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get SOFR-OIS Spread: {e}")
            errors['sofr_ois_spread'] = str(e)

        # BBB Spread
        try:
            indicators['bbb_spread'] = self.get_bbb_spread(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get BBB Spread: {e}")
            errors['bbb_spread'] = str(e)

        # Sahm Rule
        try:
            indicators['sahm_rule'] = self.get_sahm_rule(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get Sahm Rule: {e}")
            errors['sahm_rule'] = str(e)

        # Jobless Claims
        try:
            indicators['jobless_claims'] = self.get_jobless_claims(start_date=start_date)
        except Exception as e:
            logger.error(f"Failed to get Jobless Claims: {e}")
            errors['jobless_claims'] = str(e)

        logger.info(f"Collection complete. Success: {len(indicators)}, Errors: {len(errors)}")

        if errors:
            indicators['_errors'] = errors

        return indicators

    def get_latest_values(self) -> Dict[str, Any]:
        """
        Get the most recent value for each indicator

        Returns:
            Dictionary with latest values for all indicators
        """
        logger.info("Fetching latest values for all indicators...")
        data = self.collect_all_indicators(start_date='2024-01-01', period='1y')

        latest = {}

        for key, value in data.items():
            if key == '_errors':
                latest['_errors'] = value
                continue

            try:
                if isinstance(value, pd.Series):
                    latest[key] = float(value.iloc[-1])
                elif isinstance(value, pd.DataFrame):
                    latest[key] = value.iloc[-1].to_dict()
                elif isinstance(value, dict):
                    latest[key] = value
                else:
                    latest[key] = value
            except Exception as e:
                logger.warning(f"Could not extract latest value for {key}: {e}")
                latest[key] = None

        return latest


def main():
    """
    Example usage
    """
    import os
    from dotenv import load_dotenv

    # Load environment variables
    load_dotenv()

    # Initialize collector
    fred_api_key = os.getenv('FRED_API_KEY')
    if not fred_api_key:
        logger.warning("FRED_API_KEY not found in environment. Some indicators will not be available.")
        logger.info("Get your free API key at: https://fred.stlouisfed.org/docs/api/api_key.html")

    collector = EconomicDataCollector(fred_api_key=fred_api_key)

    # Example 1: Get latest values
    print("\n" + "="*60)
    print("LATEST ECONOMIC INDICATORS")
    print("="*60)

    latest = collector.get_latest_values()

    if 'vix' in latest:
        print(f"VIX: {latest['vix']:.2f}")

    if 'fear_greed' in latest and isinstance(latest['fear_greed'], dict):
        fg = latest['fear_greed']
        print(f"Fear & Greed: {fg['score']:.0f} ({fg['rating']})")

    if 'yield_curve' in latest:
        print(f"Yield Curve (10Y-2Y): {latest['yield_curve']:.3f}%")

    if 'high_yield_spread' in latest:
        print(f"High Yield Spread: {latest['high_yield_spread']:.2f}%")

    if 'bbb_spread' in latest:
        print(f"BBB Spread: {latest['bbb_spread']:.2f}%")

    if 'sahm_rule' in latest:
        sahm = latest['sahm_rule']
        print(f"Sahm Rule: {sahm:.3f} {'[RECESSION SIGNAL]' if sahm >= 0.5 else ''}")

    if 'sp500_drawdown' in latest:
        print(f"S&P 500 Drawdown: {latest['sp500_drawdown']:.2%}")

    if 'jobless_claims' in latest:
        print(f"Initial Jobless Claims: {latest['jobless_claims']:,.0f}K")

    if '_errors' in latest:
        print(f"\nErrors encountered: {len(latest['_errors'])}")
        for key, error in latest['_errors'].items():
            print(f"  - {key}: {error}")

    # Example 2: Get historical data for specific indicator
    print("\n" + "="*60)
    print("VIX - LAST 5 DAYS")
    print("="*60)

    try:
        vix = collector.get_vix(period="1mo")
        print(vix.tail())
    except Exception as e:
        print(f"Error: {e}")

    # Example 3: Check for recession signals
    print("\n" + "="*60)
    print("RECESSION SIGNALS")
    print("="*60)

    signals = []

    if 'yield_curve' in latest and latest['yield_curve'] is not None:
        if latest['yield_curve'] < 0:
            signals.append("Inverted Yield Curve")

    if 'sahm_rule' in latest and latest['sahm_rule'] is not None:
        if latest['sahm_rule'] >= 0.5:
            signals.append("Sahm Rule Triggered")

    if 'high_yield_spread' in latest and latest['high_yield_spread'] is not None:
        if latest['high_yield_spread'] > 5.0:
            signals.append("High Yield Spread Elevated")

    if 'vix' in latest and latest['vix'] is not None:
        if latest['vix'] > 30:
            signals.append("VIX Elevated (High Volatility)")

    if signals:
        print("Active recession/risk signals:")
        for signal in signals:
            print(f"  - {signal}")
    else:
        print("No major recession signals detected")

    print("\n" + "="*60)


if __name__ == "__main__":
    main()
